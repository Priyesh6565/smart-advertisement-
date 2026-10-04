"""
Targeted Video Ad Player with Hierarchical Fallback and FPS Pacing
------------------------------------------------------------------
Solves two critical issues:
1. Video speed pacing: Paces frame decoding using wall-clock time so video plays
   at its native 25/30 FPS regardless of webcam/inference loop speed.
2. Hierarchical fallback search:
   ads/<gender>/<age_bracket>/ -> ads/<gender>/ -> ads/generic/
"""

import os
import glob
import time
import cv2
import numpy as np

VIDEO_EXTENSIONS = (".mp4", ".mov", ".avi", ".mkv")
IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".bmp")
ALL_MEDIA_EXTENSIONS = VIDEO_EXTENSIONS + IMAGE_EXTENSIONS


class TargetedAdPlayer:
    def __init__(self, ads_dir=None):
        if ads_dir is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            ads_dir = os.path.join(base_dir, "ads")
        self.ads_dir = ads_dir
        self.current_folder = None
        self.media_files = []
        self.media_index = 0
        self.current_media_path = None
        self.is_image = False
        self.loaded_image = None
        self.image_display_start = 0.0
        self.image_duration = 6.0  # seconds to display an image before advancing

        self.cap = None
        self.video_fps = 30.0
        self.frame_interval = 1.0 / 30.0
        self.last_frame_time = 0.0
        self.last_frame = None

        self._ensure_default_folders()
        self.set_target("generic", "generic")

    def _ensure_default_folders(self):
        """Ensures the basic folder structure exists."""
        for sub in ["male", "female", "generic"]:
            folder = os.path.join(self.ads_dir, sub)
            os.makedirs(folder, exist_ok=True)
            for age in ["kids", "teens", "adults", "seniors"]:
                os.makedirs(os.path.join(folder, age), exist_ok=True)

    def resolve_ad_folder(self, gender, age_bracket):
        """
        Hierarchical folder resolution:
        1. ads/<gender>/<age_bracket>/
        2. ads/<gender>/
        3. ads/generic/
        """
        gender = (gender or "generic").lower()
        age_bracket = (age_bracket or "generic").lower()

        candidates = [
            os.path.join(self.ads_dir, gender, age_bracket),
            os.path.join(self.ads_dir, gender),
            os.path.join(self.ads_dir, "generic"),
        ]

        for folder in candidates:
            if os.path.isdir(folder):
                media = self._find_media_in_folder(folder)
                if len(media) > 0:
                    return folder, media

        return os.path.join(self.ads_dir, "generic"), []

    @staticmethod
    def _find_media_in_folder(folder):
        """Finds all supported video and image files in folder."""
        files = []
        try:
            for fname in os.listdir(folder):
                ext = os.path.splitext(fname)[1].lower()
                if ext in ALL_MEDIA_EXTENSIONS:
                    files.append(os.path.join(folder, fname))
        except OSError:
            pass
        return sorted(files)

    def _open_media(self, path):
        """Opens a media file (either video or image)."""
        if self.cap is not None:
            self.cap.release()
            self.cap = None

        self.current_media_path = path
        self.last_frame = None
        self.last_frame_time = 0.0

        ext = os.path.splitext(path)[1].lower()
        if ext in IMAGE_EXTENSIONS:
            self.is_image = True
            raw_img = cv2.imread(path)
            if raw_img is not None:
                self.loaded_image = cv2.resize(raw_img, (1280, 720), interpolation=cv2.INTER_AREA)
            else:
                self.loaded_image = None
            self.image_display_start = time.time()
        else:
            self.is_image = False
            self.loaded_image = None
            self.cap = cv2.VideoCapture(path)
            fps = self.cap.get(cv2.CAP_PROP_FPS)
            self.video_fps = fps if (fps and 10.0 <= fps <= 60.0) else 30.0
            self.frame_interval = 1.0 / self.video_fps

    def _advance_media(self):
        """Advances to the next media item in the current folder playlist."""
        if not self.media_files:
            return
        self.media_index = (self.media_index + 1) % len(self.media_files)
        self._open_media(self.media_files[self.media_index])

    def set_target(self, gender, age_bracket):
        """Switches playback target if the resolved folder differs from current."""
        target_folder, media = self.resolve_ad_folder(gender, age_bracket)
        if target_folder != self.current_folder or not self.media_files:
            self.current_folder = target_folder
            self.media_files = media
            self.media_index = 0
            if len(self.media_files) > 0:
                self._open_media(self.media_files[0])
            else:
                if self.cap is not None:
                    self.cap.release()
                    self.cap = None
                self.current_media_path = None
                self.loaded_image = None
                self.last_frame = None

    def get_frame(self, gender, age_bracket):
        """
        Paces ad playback using wall-clock time.
        Returns a (720, 1280, 3) frame ready for display.
        """
        self.set_target(gender, age_bracket)

        # Case 1: Image media
        if self.is_image:
            if self.loaded_image is None:
                return self._placeholder("Could not load image ad", gender, age_bracket)

            # Check if duration elapsed and multiple media exist in playlist
            if len(self.media_files) > 1 and (time.time() - self.image_display_start) > self.image_duration:
                self._advance_media()
                if self.loaded_image is not None:
                    return self.loaded_image

            return self.loaded_image

        # Case 2: No video opened
        if self.cap is None or not self.cap.isOpened():
            rel_folder = os.path.relpath(self.current_folder or self.ads_dir, self.ads_dir)
            return self._placeholder(f"No media found in ads/{rel_folder}/", gender, age_bracket)

        # Case 3: Video playback with wall-clock pacing
        now = time.time()
        if self.last_frame is not None and (now - self.last_frame_time) < self.frame_interval:
            return self.last_frame

        ok, frame = self.cap.read()
        if not ok:
            # If multiple media in playlist, cycle to next
            if len(self.media_files) > 1:
                self._advance_media()
                if self.cap is not None and self.cap.isOpened():
                    ok, frame = self.cap.read()
            else:
                # Loop current video
                self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ok, frame = self.cap.read()
                if not ok:
                    # Fallback reopen if codec fails POS_FRAMES
                    self.cap.release()
                    self.cap = cv2.VideoCapture(self.current_media_path)
                    ok, frame = self.cap.read()

            if not ok or frame is None:
                return self._placeholder("Error decoding video", gender, age_bracket)

        self.last_frame_time = now
        if frame.shape[0] != 720 or frame.shape[1] != 1280:
            frame = cv2.resize(frame, (1280, 720), interpolation=cv2.INTER_LINEAR)

        self.last_frame = frame
        return frame

    def _placeholder(self, message, gender, age_bracket):
        img = np.zeros((720, 1280, 3), dtype=np.uint8)
        img[:] = (24, 20, 18)

        # Sleek header bar
        cv2.rectangle(img, (0, 0), (1280, 80), (35, 30, 25), -1)
        cv2.putText(img, "SMART DIGITAL SIGNAGE SYSTEM", (50, 52),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.1, (240, 240, 240), 2)

        info = f"Current Target: {gender.upper()} / {age_bracket.upper()}"
        cv2.putText(img, info, (80, 250),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 215, 255), 2)

        cv2.putText(img, message, (80, 350),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.85, (180, 180, 180), 2)

        hint = "Add video (.mp4) or image (.png, .jpg) to ads/<gender>/<age>/ or ads/<gender>/"
        cv2.putText(img, hint, (80, 450),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (120, 120, 120), 1)

        self.last_frame = img
        return img

    def release(self):
        if self.cap is not None:
            self.cap.release()
            self.cap = None
