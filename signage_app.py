"""
Laptop-only Digital Signage: Age/Gender Detection + Targeted VIDEO Ad Player
------------------------------------------------------------------------------
Uses InsightFace's "buffalo_l" model pack for face detection + age/gender.

Runs entirely on your laptop using the built-in webcam. No Firebase,
Flutter, MQTT, or Raspberry Pi hardware needed.

FIRST RUN NOTE: the first time you run this, InsightFace will automatically
download the buffalo_l model pack (~280MB) to ~/.insightface/models/. This
needs an internet connection once; after that it's cached locally and works
offline.

Two windows:
  - "Camera" : debug window with every detected face's box + gender + age +
               REAL gender confidence (the model's own softmax probability).
               Two status lines at the bottom:
                 "Raw (this frame): ..."     <- can vary frame to frame, normal
                 "Showing ad (stable): ..."  <- what's actually playing
  - "Ads"    : fullscreen window that plays video ads based on the STABLE
               category.

Controls:
  q  -> quit
  f  -> toggle fullscreen on the Ads window

Folder layout expected:
  ads/male/*.mp4 (or .mov / .avi)
  ads/female/*.mp4
  ads/generic/*.mp4
"""

import cv2
import numpy as np
import os
import time
import glob
from collections import deque

from insightface.app import FaceAnalysis
from insightface.utils import face_align

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ADS_DIR = os.path.join(BASE_DIR, "ads")

# --- Reliability filtering thresholds ---
# Pose (yaw/pitch) turned out NOT to reliably predict correctness: tested
# directly against real footage, a ~49 degree yaw face with 98% gender
# confidence was a CORRECT read that a pose cutoff was blocking, while a
# DIFFERENT ~50 degree yaw face with 92% confidence was a WRONG read.
# Since pose doesn't cleanly separate these, the primary gate is now the
# model's own gender confidence, with only a generous pose backstop for
# truly degenerate near-profile crops where face alignment itself breaks
# down (not for filtering "is this probably correct").
DET_SCORE_THRESHOLD = 0.5         # minimum face-detector confidence to trust a face at all
GENDER_CONF_THRESHOLD = 0.60      # minimum gender-prediction confidence to count a face
MAX_YAW_DEGREES = 70               # generous backstop -- only excludes near-full-profile shots
MAX_PITCH_DEGREES = 55
EDGE_MARGIN_PX = 8                 # face box touching the frame border by less than this -> likely cut off

NO_FACE_TIMEOUT_SECONDS = 2        # fall back to generic ads if nobody detected
SMOOTHING_WINDOW_SECONDS = 2.5     # ad category only switches after being the majority over this window;
                                    # widened from 1.5s so the occasional high-confidence-but-wrong frame
                                    # (unavoidable with any threshold, see note above) gets averaged out
                                    # rather than flipping the ad on its own

CAPTURE_WIDTH = 1280
CAPTURE_HEIGHT = 720

VIDEO_EXTENSIONS = ("*.mp4", "*.mov", "*.avi", "*.mkv")

print("Loading InsightFace buffalo_l model pack (first run downloads ~280MB, then it's cached)...")
face_app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
face_app.prepare(ctx_id=-1, det_size=(640, 640))
attr_model = face_app.models["genderage"]
print("Model ready.")


def get_gender_confidence(img, face):
    """Recovers the real softmax probability for the predicted gender (not exposed by the high-level API)."""
    bbox = face.bbox
    w, h = (bbox[2] - bbox[0]), (bbox[3] - bbox[1])
    center = (bbox[2] + bbox[0]) / 2, (bbox[3] + bbox[1]) / 2
    scale = attr_model.input_size[0] / (max(w, h) * 1.5)
    aligned, _ = face_align.transform(img, center, attr_model.input_size[0], scale, 0)
    input_size = tuple(aligned.shape[0:2][::-1])
    blob = cv2.dnn.blobFromImage(aligned, 1.0 / attr_model.input_std, input_size,
                                  (attr_model.input_mean,) * 3, swapRB=True)
    pred = attr_model.session.run(attr_model.output_names, {attr_model.input_name: blob})[0][0]
    gender_logits = pred[:2]
    exp = np.exp(gender_logits - np.max(gender_logits))
    probs = exp / exp.sum()
    return float(probs.max())


def is_reliable(face, gender_conf, frame_w, frame_h):
    """
    Primary gate is gender-prediction confidence (the thing we actually
    care about being right). Pose and edge-cutoff remain as backstops for
    genuinely degenerate cases, not as the main filter.
    """
    if face.det_score < DET_SCORE_THRESHOLD:
        return False
    if gender_conf < GENDER_CONF_THRESHOLD:
        return False

    pose = getattr(face, "pose", None)
    if pose is not None:
        pitch, yaw, roll = pose
        if abs(yaw) > MAX_YAW_DEGREES or abs(pitch) > MAX_PITCH_DEGREES:
            return False

    x1, y1, x2, y2 = face.bbox
    if x1 <= EDGE_MARGIN_PX or y1 <= EDGE_MARGIN_PX or \
       x2 >= frame_w - EDGE_MARGIN_PX or y2 >= frame_h - EDGE_MARGIN_PX:
        return False

    return True


def decide_category_by_ratio(male_count, female_count, tie_toggle):
    """Majority gender wins; exact tie alternates fairly. Returns (category, updated_tie_toggle)."""
    if male_count == 0 and female_count == 0:
        return "generic", tie_toggle
    if male_count > female_count:
        return "male", tie_toggle
    if female_count > male_count:
        return "female", tie_toggle
    return ("male" if tie_toggle else "female"), (not tie_toggle)


class CategorySmoother:
    """Only reports a category change once it's been the majority over SMOOTHING_WINDOW_SECONDS."""
    def __init__(self, window_seconds):
        self.window_seconds = window_seconds
        self.history = deque()
        self.current = "generic"

    def update(self, category):
        now = time.time()
        self.history.append((now, category))
        while self.history and now - self.history[0][0] > self.window_seconds:
            self.history.popleft()
        counts = {}
        for _, cat in self.history:
            counts[cat] = counts.get(cat, 0) + 1
        self.current = max(counts, key=counts.get)
        return self.current


class VideoAdPlayer:
    """Plays video ad files for a category, rotating and looping; reopens automatically on category change."""
    def __init__(self, ads_dir):
        self.library = {
            "male": self._load_videos(ads_dir, "male"),
            "female": self._load_videos(ads_dir, "female"),
            "generic": self._load_videos(ads_dir, "generic"),
        }
        for cat, files in self.library.items():
            print(f"[ads] {cat}: {len(files)} video(s) loaded")
            if not files:
                print(f"  -> put at least one .mp4 in ads/{cat}/  (a placeholder will be shown otherwise)")

        self.index = {cat: 0 for cat in self.library}
        self.category = None
        self.cap = None
        self._open_current("generic")

    @staticmethod
    def _load_videos(ads_dir, category):
        files = []
        for ext in VIDEO_EXTENSIONS:
            files.extend(glob.glob(os.path.join(ads_dir, category, ext)))
        return sorted(files)

    def _open_current(self, category):
        if self.cap is not None:
            self.cap.release()
            self.cap = None
        self.category = category
        files = self.library.get(category) or []
        if not files:
            return
        path = files[self.index[category] % len(files)]
        self.cap = cv2.VideoCapture(path)

    def _advance_to_next_video(self):
        self.index[self.category] = (self.index[self.category] + 1) % max(len(self.library[self.category]), 1)
        self._open_current(self.category)

    def get_frame(self, category):
        if category != self.category:
            self._open_current(category)

        files = self.library.get(category) or []
        if not files or self.cap is None:
            return self._placeholder(f"No video ads found for: {category}")

        ok, frame = self.cap.read()
        if not ok:
            self._advance_to_next_video()
            if self.cap is None:
                return self._placeholder(f"No video ads found for: {category}")
            ok, frame = self.cap.read()
            if not ok:
                return self._placeholder(f"Could not read video for: {category}")
        return frame

    @staticmethod
    def _placeholder(text):
        img = np.zeros((720, 1280, 3), dtype=np.uint8)
        cv2.putText(img, text, (60, 360), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 3)
        return img


def draw_label(frame, x1, y1, x2, y2, text, box_color):
    """Draws the face box and label, keeping the label fully inside the frame (never clipped at edges)."""
    frame_h, frame_w = frame.shape[:2]
    cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, 2)

    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale, thickness = 0.5, 2
    (text_w, text_h), _ = cv2.getTextSize(text, font, font_scale, thickness)

    label_y = y1 - 10
    if label_y - text_h < 0:
        label_y = y2 + text_h + 10
    label_y = min(max(label_y, text_h + 2), frame_h - 2)
    label_x = min(max(x1, 2), frame_w - text_w - 2)

    cv2.rectangle(frame, (label_x - 2, label_y - text_h - 4), (label_x + text_w + 2, label_y + 4), (0, 0, 0), -1)
    cv2.putText(frame, text, (label_x, label_y), font, font_scale, (0, 255, 0), thickness)


def draw_status_lines(frame, raw_text, stable_text):
    """Draws the two status lines at the bottom, each on its own background bar."""
    frame_h, frame_w = frame.shape[:2]
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale, thickness = 0.5, 1

    for i, (text, color) in enumerate([(raw_text, (255, 255, 0)), (stable_text, (0, 255, 255))]):
        (text_w, text_h), _ = cv2.getTextSize(text, font, font_scale, thickness)
        y = frame_h - 10 - i * (text_h + 14)
        cv2.rectangle(frame, (5, y - text_h - 6), (min(15 + text_w, frame_w - 5), y + 4), (0, 0, 0), -1)
        cv2.putText(frame, text, (10, y), font, font_scale, color, thickness)


def main():
    backend = cv2.CAP_AVFOUNDATION if hasattr(cv2, "CAP_AVFOUNDATION") else cv2.CAP_ANY
    cap = cv2.VideoCapture(0, backend)
    if not cap.isOpened():
        raise RuntimeError(
            "Could not open the webcam.\n"
            "On macOS this is almost always a camera-permission issue:\n"
            "  1. System Settings -> Privacy & Security -> Camera\n"
            "  2. Enable access for Terminal (or iTerm/VS Code, whichever you're running from)\n"
            "  3. Fully quit and reopen the terminal app, then re-run this script\n"
            "If it's still not working, try changing VideoCapture(0, ...) to VideoCapture(1, ...) "
            "in case your laptop has more than one camera, or make sure no other app "
            "(Zoom, FaceTime, browser tab) is currently using the camera."
        )
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

    warm_up_ok = False
    for _ in range(30):
        ok, _ = cap.read()
        if ok:
            warm_up_ok = True
            break
        time.sleep(0.1)
    if not warm_up_ok:
        cap.release()
        raise RuntimeError(
            "Webcam opened but never returned a usable frame after ~3 seconds.\n"
            "This is almost always the macOS camera permission not being granted yet.\n"
            "Go to System Settings -> Privacy & Security -> Camera, enable Terminal, "
            "fully quit/reopen Terminal, then run this script again."
        )

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Camera capture resolution: {actual_w}x{actual_h}")

    cv2.namedWindow("Ads", cv2.WINDOW_NORMAL)
    fullscreen = True
    cv2.setWindowProperty("Ads", cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)

    ad_player = VideoAdPlayer(ADS_DIR)
    smoother = CategorySmoother(SMOOTHING_WINDOW_SECONDS)

    last_face_seen = 0
    tie_toggle = True

    print("Press 'q' in either window to quit, 'f' to toggle fullscreen on the Ads window.")

    consecutive_failures = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            consecutive_failures += 1
            if consecutive_failures > 30:
                print("Webcam stopped returning frames. Exiting.")
                break
            continue
        consecutive_failures = 0

        frame_h, frame_w = frame.shape[:2]
        faces = face_app.get(frame)
        raw_category = "generic"
        male_count = female_count = 0

        if len(faces) > 0:
            last_face_seen = time.time()

            for f in faces:
                x1, y1, x2, y2 = f.bbox.astype(int)
                gender = "Male" if f.sex == "M" else "Female"
                age = int(f.age)
                gender_conf = get_gender_confidence(frame, f)
                reliable = is_reliable(f, gender_conf, frame_w, frame_h)

                if reliable:
                    if gender == "Male":
                        male_count += 1
                        box_color = (0, 0, 255)
                    else:
                        female_count += 1
                        box_color = (255, 0, 255)
                    label = f"{gender}, {age} ({gender_conf:.0%})"
                else:
                    box_color = (128, 128, 128)
                    label = f"Uncertain: {gender}? ({gender_conf:.0%})"

                draw_label(frame, x1, y1, x2, y2, label, box_color)

            raw_category, tie_toggle = decide_category_by_ratio(male_count, female_count, tie_toggle)
        else:
            if time.time() - last_face_seen > NO_FACE_TIMEOUT_SECONDS:
                raw_category = "generic"
            else:
                raw_category = smoother.current

        stable_category = smoother.update(raw_category)

        raw_text = f"Raw (this frame): {male_count} male, {female_count} female -> {raw_category}"
        stable_text = f"Showing ad (stable): {stable_category}"
        draw_status_lines(frame, raw_text, stable_text)

        cv2.imshow("Camera", frame)

        ad_frame = ad_player.get_frame(stable_category)
        cv2.imshow("Ads", ad_frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('f'):
            fullscreen = not fullscreen
            cv2.setWindowProperty(
                "Ads", cv2.WND_PROP_FULLSCREEN,
                cv2.WINDOW_FULLSCREEN if fullscreen else cv2.WINDOW_NORMAL
            )

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
