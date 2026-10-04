"""
AI-Powered Audience-Targeted Digital Signage System
--------------------------------------------------
Optimized for Indian demographic accuracy and real-time laptop CPU execution.

Pipeline Architecture:
1. Face Detection: InsightFace SCRFD / OpenCV YuNet ONNX.
2. Demographic Analysis: FairFace ONNX (trained on race-balanced dataset with 15k+ Indian faces).
3. Person-Level Tracking: Centroid + IoU tracker with Exponential Moving Average (EMA)
   demographic probability smoothing per person.
4. Ad Targeting: Multi-tier fallback (ads/<gender>/<age_bracket>/ -> ads/<gender>/ -> ads/generic/).
5. Paced Media Player: Wall-clock FPS pacing for video ads and timed banner ad rotation.

Controls:
  'q' -> Quit
  'f' -> Toggle Fullscreen for Ads display
"""

import os
import sys
import time
from collections import deque
import cv2
import numpy as np

# Local modular components
from tracker import FaceTracker
from fairface_engine import FairFaceEngine, FAIRFACE_AGES, map_bracket_to_category
from ad_manager import TargetedAdPlayer
from detector import UnifiedFaceDetector

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ADS_DIR = os.path.join(BASE_DIR, "ads")
MODELS_DIR = os.path.join(BASE_DIR, "models")
FAIRFACE_MODEL_PATH = os.path.join(MODELS_DIR, "fairface.onnx")
YUNET_MODEL_PATH = os.path.join(MODELS_DIR, "face_detection_yunet.onnx")

# --- Quality & Reliability Thresholds ---
DET_SCORE_THRESHOLD = 0.45         # Minimum face detector confidence
MIN_FACE_SIZE_PX = 45              # Minimum face dimension in pixels for demographic classification
MIN_IPD_PX = 14                    # Inter-Pupillary Distance (distance between eyes in pixels)
NO_FACE_TIMEOUT_SECONDS = 2.0      # Revert to generic ads if camera is empty for this duration
TARGET_SMOOTHING_SECONDS = 1.5     # Smooth audience transitions to prevent mid-scene ad flickering

CAPTURE_WIDTH = 1280
CAPTURE_HEIGHT = 720


def initialize_detector(backend="auto"):
    """Initializes high-performance face detector (InsightFace SCRFD or YuNet ONNX)."""
    return UnifiedFaceDetector(yunet_path=YUNET_MODEL_PATH, prefer_insightface=True, backend=backend)


def check_face_quality(bbox, landmarks, frame_w, frame_h):
    """
    Physical quality gate:
    Checks face bounding box size, edge clamping, and Inter-Pupillary Distance (IPD).
    Returns: (is_valid: bool, reason: str, clamped_bbox: np.ndarray)
    """
    x1, y1, x2, y2 = bbox
    cx1 = max(0, x1)
    cy1 = max(0, y1)
    cx2 = min(frame_w, x2)
    cy2 = min(frame_h, y2)
    clamped_box = np.array([cx1, cy1, cx2, cy2], dtype=int)

    w = max(0, cx2 - cx1)
    h = max(0, cy2 - cy1)

    if w < MIN_FACE_SIZE_PX or h < MIN_FACE_SIZE_PX:
        return False, "Too distant", clamped_box

    # Ensure at least 60% of original area is inside frame
    orig_area = max(1, (x2 - x1) * (y2 - y1))
    visible_area = w * h
    if visible_area / orig_area < 0.60:
        return False, "Clipped by edge", clamped_box

    if landmarks is not None and len(landmarks) >= 2:
        # Landmarks: [0] = right eye, [1] = left eye
        right_eye = landmarks[0]
        left_eye = landmarks[1]
        ipd = np.linalg.norm(np.array(right_eye) - np.array(left_eye))
        if ipd < MIN_IPD_PX:
            return False, "Low resolution", clamped_box

    return True, "OK", clamped_box


class AudienceTargetSmoother:
    """Smooths audience majority decisions across a temporal window."""

    def __init__(self, window_seconds=1.5):
        self.window_seconds = window_seconds
        self.history = deque()
        self.current_target = ("generic", "generic")

    def update(self, raw_gender, raw_age_category):
        now = time.time()
        self.history.append((now, (raw_gender, raw_age_category)))

        # Evict old entries
        while self.history and (now - self.history[0][0]) > self.window_seconds:
            self.history.popleft()

        # Majority vote across window
        counts = {}
        for _, target in self.history:
            counts[target] = counts.get(target, 0) + 1

        if counts:
            self.current_target = max(counts, key=counts.get)
        return self.current_target


def draw_detection_overlay(frame, tracks, raw_stats, stable_target, unconfirmed_boxes=None, fps=0.0):
    """Draws sleek HUD overlays, face bounding boxes, and demographics."""
    frame_h, frame_w = frame.shape[:2]

    # Draw unconfirmed / raw faces in subtle gray/yellow
    if unconfirmed_boxes:
        for ubox, reason in unconfirmed_boxes:
            ux1, uy1, ux2, uy2 = ubox
            cv2.rectangle(frame, (ux1, uy1), (ux2, uy2), (100, 160, 200), 1, cv2.LINE_AA)
            if reason != "OK":
                cv2.putText(frame, reason, (ux1, max(uy1 - 6, 15)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.45, (140, 180, 220), 1, cv2.LINE_AA)

    # Draw confirmed audience tracks
    for t in tracks:
        x1, y1, x2, y2 = t.bbox.astype(int)
        gender, gender_conf = t.get_gender()
        age_bracket, age_conf = t.get_age_bracket(FAIRFACE_AGES)
        age_cat = map_bracket_to_category(age_bracket)

        # Color coding: Cyan for Male, Magenta for Female
        box_color = (255, 180, 0) if gender == "Male" else (220, 60, 255)
        cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, 2, cv2.LINE_AA)

        label = f"#{t.track_id} {gender} ({gender_conf:.0%}) | {age_bracket} ({age_cat.capitalize()})"
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale, thickness = 0.52, 1
        (text_w, text_h), _ = cv2.getTextSize(label, font, font_scale, thickness)

        label_y = max(y1 - 10, text_h + 10)
        label_x = min(max(x1, 5), frame_w - text_w - 5)

        # Pill background
        cv2.rectangle(frame, (label_x - 5, label_y - text_h - 5),
                      (label_x + text_w + 5, label_y + 4), (18, 18, 18), -1)
        cv2.rectangle(frame, (label_x - 5, label_y - text_h - 5),
                      (label_x + text_w + 5, label_y + 4), box_color, 1)
        cv2.putText(frame, label, (label_x, label_y), font, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)

    # Top Status Bar
    cv2.rectangle(frame, (0, 0), (frame_w, 42), (15, 15, 15), -1)
    status_left = f"Audience Active: {raw_stats['male']} Male, {raw_stats['female']} Female | Dominant: {raw_stats['dom_age'].upper()}"
    cv2.putText(frame, status_left, (15, 27), cv2.FONT_HERSHEY_SIMPLEX, 0.60, (0, 255, 200), 1, cv2.LINE_AA)

    fps_text = f"FPS: {fps:.1f}"
    (fps_w, _), _ = cv2.getTextSize(fps_text, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
    cv2.putText(frame, fps_text, (frame_w - fps_w - 15, 27), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 200), 1, cv2.LINE_AA)

    # Check for closed webcam privacy shutter / zero light
    if frame.mean() < 8.0:
        cv2.rectangle(frame, (frame_w // 2 - 380, frame_h // 2 - 50),
                      (frame_w // 2 + 380, frame_h // 2 + 50), (0, 0, 180), -1)
        cv2.rectangle(frame, (frame_w // 2 - 380, frame_h // 2 - 50),
                      (frame_w // 2 + 380, frame_h // 2 + 50), (0, 255, 255), 2)
        cv2.putText(frame, "WEBCAM FEED IS BLACK",
                    (frame_w // 2 - 200, frame_h // 2 - 12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)
        cv2.putText(frame, "Please slide open your physical laptop webcam shutter / press camera Fn key!",
                    (frame_w // 2 - 360, frame_h // 2 + 25),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (220, 255, 255), 1)

    # Bottom Status Bar
    cv2.rectangle(frame, (0, frame_h - 42), (frame_w, frame_h), (15, 15, 15), -1)
    status_bottom = f"Displaying Ad Category: {stable_target[0].upper()} / {stable_target[1].upper()}"
    cv2.putText(frame, status_bottom, (15, frame_h - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.60, (50, 200, 255), 1, cv2.LINE_AA)


def run_mock_generator():
    """Generates synthetic camera frames cycling through scenarios for testing."""
    h, w = 720, 1280
    state_start = time.time()
    state = 0  # 0: empty, 1: male adult, 2: female teen, 3: group
    synthetic_faces = [
        # Male adult face coordinates
        [{"bbox": [480, 200, 680, 450], "gender_probs": [0.94, 0.06], "age_probs": [0.01, 0.01, 0.02, 0.85, 0.08, 0.02, 0.01, 0.0, 0.0], "age_category": "adults"}],
        # Female teen face coordinates
        [{"bbox": [520, 220, 700, 440], "gender_probs": [0.05, 0.95], "age_probs": [0.02, 0.05, 0.82, 0.08, 0.02, 0.01, 0.0, 0.0, 0.0], "age_category": "teens"}],
        # Group (Male adult + Female adult)
        [
            {"bbox": [320, 210, 500, 440], "gender_probs": [0.92, 0.08], "age_probs": [0.01, 0.02, 0.05, 0.82, 0.08, 0.01, 0.01, 0.0, 0.0], "age_category": "adults"},
            {"bbox": [720, 220, 900, 450], "gender_probs": [0.08, 0.92], "age_probs": [0.01, 0.02, 0.04, 0.83, 0.08, 0.01, 0.01, 0.0, 0.0], "age_category": "adults"}
        ],
    ]

    while True:
        elapsed = time.time() - state_start
        if elapsed > 7.0:
            state = (state + 1) % 4
            state_start = time.time()

        frame = np.zeros((h, w, 3), dtype=np.uint8)
        frame[:] = (32, 28, 25)
        cv2.putText(frame, f"[MOCK SIMULATION MODE - Stage {state}]", (40, 70),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 180), 2)

        if state == 0:
            cv2.putText(frame, "Scenario: Empty Room / Waiting for audience", (40, 120),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (180, 180, 180), 1)
            yield frame, []
        else:
            scenario_name = ["Male Adult", "Female Teen", "Multi-Person Group"][state - 1]
            cv2.putText(frame, f"Scenario: {scenario_name}", (40, 120),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (180, 180, 180), 1)
            dets = synthetic_faces[state - 1]
            for d in dets:
                bx1, by1, bx2, by2 = d["bbox"]
                # Draw synthetic face avatar
                cv2.ellipse(frame, ((bx1 + bx2) // 2, (by1 + by2) // 2),
                            ((bx2 - bx1) // 2, int((by2 - by1) * 0.55)), 0, 0, 360, (190, 170, 150), -1)
            yield frame, dets
        time.sleep(0.033)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="AI-Powered Targeted Digital Signage")
    parser.add_argument("--source", default="0", help="Webcam index (e.g. 0, 1) or path to video file")
    parser.add_argument("--detector", default="auto", choices=["auto", "insightface", "yunet"],
                        help="Face detection engine (auto, insightface, yunet)")
    parser.add_argument("--mock", action="store_true", help="Run with synthetic simulated audience feed")
    parser.add_argument("--fullscreen", action="store_true", help="Start Ads Display in fullscreen mode")
    args = parser.parse_args()

    print("=" * 65)
    print("  AI-Powered Audience-Targeted Digital Signage System")
    print("  Demographic Model: FairFace (Balanced for Indian Demographics)")
    print("=" * 65)

    # 1. Initialize Face Detector
    detector = initialize_detector(backend=args.detector)

    # 2. Initialize Demographic Engine (FairFace ONNX)
    if os.path.exists(FAIRFACE_MODEL_PATH):
        fairface = FairFaceEngine(FAIRFACE_MODEL_PATH)
    else:
        print(f"[Warning] FairFace model not found at {FAIRFACE_MODEL_PATH}.")
        fairface = None

    # 3. Initialize Tracker, Ad Player & Smoother
    tracker = FaceTracker(iou_threshold=0.3, max_lost_frames=20, min_hits_to_confirm=2, ema_alpha=0.25)
    ad_player = TargetedAdPlayer(ADS_DIR)
    smoother = AudienceTargetSmoother(window_seconds=TARGET_SMOOTHING_SECONDS)

    # 4. Open Webcam or Video source
    mock_gen = None
    cap = None
    source = None

    if args.mock:
        print("[Mode] Running in mock simulation mode.")
        mock_gen = run_mock_generator()
    else:
        source = int(args.source) if args.source.isdigit() else args.source
        if isinstance(source, int):
            # DirectShow on Windows opens laptop webcams reliably
            if hasattr(cv2, "CAP_DSHOW"):
                cap = cv2.VideoCapture(source, cv2.CAP_DSHOW)
            elif hasattr(cv2, "CAP_AVFOUNDATION"):
                cap = cv2.VideoCapture(source, cv2.CAP_AVFOUNDATION)

        if cap is None or not cap.isOpened():
            cap = cv2.VideoCapture(source, cv2.CAP_ANY)

        if not cap.isOpened():
            print(f"[Error] Could not open video source: '{source}'.")
            print("Please ensure your camera is connected and not locked by another app.")
            sys.exit(1)

        if isinstance(source, int):
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAPTURE_WIDTH)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAPTURE_HEIGHT)

            # Drain initial black/unexposed warm-up frames
            print("[Camera] Warming up webcam sensor...")
            for _ in range(12):
                cap.read()
                time.sleep(0.02)

    # 5. Window setup & layout positioning
    cam_win = "Audience Analysis Camera"
    ad_win = "Ads Display"

    cv2.namedWindow(cam_win, cv2.WINDOW_NORMAL)
    cv2.namedWindow(ad_win, cv2.WINDOW_NORMAL)

    cv2.resizeWindow(cam_win, 640, 420)
    cv2.moveWindow(cam_win, 40, 60)

    cv2.resizeWindow(ad_win, 854, 480)
    cv2.moveWindow(ad_win, 700, 60)

    fullscreen = args.fullscreen
    if fullscreen:
        cv2.setWindowProperty(ad_win, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)

    last_active_audience_time = 0
    stable_target = ("generic", "generic")
    consecutive_failures = 0

    fps = 0.0
    frame_times = deque(maxlen=20)
    last_loop_time = time.time()

    print("[Ready] Running live pipeline.")
    print("Controls: Press 'q' to quit | 'f' to toggle fullscreen on Ads Display.")

    try:
        while True:
            loop_now = time.time()
            dt = loop_now - last_loop_time
            last_loop_time = loop_now
            if dt > 0:
                frame_times.append(1.0 / dt)
                fps = sum(frame_times) / len(frame_times)

            # Check if windows were closed via the 'X' button
            cam_vis = cv2.getWindowProperty(cam_win, cv2.WND_PROP_VISIBLE)
            ad_vis = cv2.getWindowProperty(ad_win, cv2.WND_PROP_VISIBLE)
            if cam_vis < 1 and ad_vis < 1:
                print("[Info] Application windows closed. Exiting.")
                break

            # Read frame
            if mock_gen is not None:
                frame, mock_dets = next(mock_gen)
            else:
                ok, frame = cap.read()
                if not ok:
                    if not isinstance(source, int):
                        # Video file reached end -> loop it
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        ok, frame = cap.read()

                    if not ok:
                        consecutive_failures += 1
                        if consecutive_failures > 50:
                            print("[Error] Camera feed disconnected or stopped sending frames.")
                            break
                        time.sleep(0.02)
                        continue

                consecutive_failures = 0

            frame_h, frame_w = frame.shape[:2]

            # Step 1: Detect Faces & Demographics
            valid_detections = []
            unconfirmed_boxes = []

            if mock_gen is not None:
                valid_detections = mock_dets
            else:
                raw_faces = detector.get(frame)
                for f in raw_faces:
                    score = getattr(f, "det_score", 1.0)
                    bbox = f.bbox.astype(int)
                    landmarks = getattr(f, "kps", None)

                    if score < DET_SCORE_THRESHOLD:
                        unconfirmed_boxes.append((bbox, f"Uncertain ({score:.0%})"))
                        continue

                    is_valid, reason, clamped_bbox = check_face_quality(bbox, landmarks, frame_w, frame_h)
                    if not is_valid:
                        unconfirmed_boxes.append((clamped_bbox, reason))
                        continue

                    # Step 2: Demographic Inference with FairFace
                    if fairface is not None:
                        demo = fairface.predict(frame, clamped_bbox)
                        if demo is not None:
                            valid_detections.append({
                                'bbox': clamped_bbox,
                                'gender_probs': demo['gender_probs'],
                                'age_probs': demo['age_probs'],
                                'age_category': demo['age_category'],
                            })
                    else:
                        valid_detections.append({
                            'bbox': clamped_bbox,
                            'gender_probs': [0.85, 0.15],
                            'age_probs': [0.1] * len(FAIRFACE_AGES),
                            'age_category': 'adults',
                        })

            # Step 3: Person Tracking & Temporal Smoothing
            tracker.update(valid_detections)
            confirmed_tracks = tracker.get_confirmed_tracks()

            male_count = 0
            female_count = 0
            age_cat_counts = {}

            if len(confirmed_tracks) > 0:
                last_active_audience_time = time.time()
                for t in confirmed_tracks:
                    gender, _ = t.get_gender()
                    bracket, _ = t.get_age_bracket(FAIRFACE_AGES)
                    cat = map_bracket_to_category(bracket)

                    if gender == "Male":
                        male_count += 1
                    else:
                        female_count += 1

                    age_cat_counts[cat] = age_cat_counts.get(cat, 0) + 1

                # Majority gender (retain stable on exact tie)
                if male_count > female_count:
                    raw_gender = "male"
                elif female_count > male_count:
                    raw_gender = "female"
                else:
                    raw_gender = stable_target[0] if stable_target[0] in ["male", "female"] else "male"

                dominant_age = max(age_cat_counts, key=age_cat_counts.get) if age_cat_counts else "adults"
                raw_target = (raw_gender, dominant_age)
            else:
                dominant_age = "none"
                if time.time() - last_active_audience_time > NO_FACE_TIMEOUT_SECONDS:
                    raw_target = ("generic", "generic")
                else:
                    raw_target = stable_target

            # Step 4: Windowed Majority Target Smoothing
            stable_target = smoother.update(raw_target[0], raw_target[1])

            # Step 5: Render Ads
            ad_frame = ad_player.get_frame(stable_target[0], stable_target[1])
            cv2.imshow(ad_win, ad_frame)

            # Step 6: Render Camera HUD
            raw_stats = {
                'male': male_count,
                'female': female_count,
                'dom_age': dominant_age
            }
            draw_detection_overlay(frame, confirmed_tracks, raw_stats, stable_target,
                                   unconfirmed_boxes=unconfirmed_boxes, fps=fps)
            cv2.imshow(cam_win, frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('f'):
                fullscreen = not fullscreen
                cv2.setWindowProperty(
                    ad_win, cv2.WND_PROP_FULLSCREEN,
                    cv2.WINDOW_FULLSCREEN if fullscreen else cv2.WINDOW_NORMAL
                )

    finally:
        if cap is not None:
            cap.release()
        ad_player.release()
        cv2.destroyAllWindows()
        print("[Shutdown] Cleaned up resources. Goodbye!")


if __name__ == "__main__":
    main()
