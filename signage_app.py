"""
Laptop-only Digital Signage: Age/Gender Detection + Targeted Ad Slideshow
--------------------------------------------------------------------------
Uses InsightFace's "buffalo_l" model pack for face detection + age/gender
estimation -- trained on a much larger, more diverse face dataset than the
old Levi & Hassner (2015) Adience-based Caffe model, and verified in testing
to correctly classify faces the old model got wrong.

Runs entirely on your laptop using the built-in webcam. No Firebase,
Flutter, MQTT, or Raspberry Pi hardware needed.

FIRST RUN NOTE: the first time you run this, InsightFace will automatically
download the buffalo_l model pack (~280MB) to ~/.insightface/models/. This
needs an internet connection once; after that it's cached locally and works
offline.

Two windows:
  - "Camera" : debug window showing every detected face + predicted age/gender
               + detection confidence, plus a running male/female count
  - "Ads"    : fullscreen window that rolls advertisement images based on
               the MAJORITY gender currently in front of the camera
               (e.g. 3 men + 1 woman -> male ads; exact ties alternate fairly)

Controls:
  q  -> quit
  f  -> toggle fullscreen on the Ads window

Folder layout expected:
  ads/male/*.jpg or *.png
  ads/female/*.jpg or *.png
  ads/generic/*.jpg or *.png
"""

import cv2
import numpy as np
import os
import time
import glob

from insightface.app import FaceAnalysis

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ADS_DIR = os.path.join(BASE_DIR, "ads")

DET_SCORE_THRESHOLD = 0.5      # below this, a detected face is excluded from the male/female count
AD_SWITCH_SECONDS = 4          # how long each ad image stays on screen
NO_FACE_TIMEOUT_SECONDS = 2    # fall back to generic ads if nobody detected

print("Loading InsightFace buffalo_l model pack (first run downloads ~280MB, then it's cached)...")
face_app = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
face_app.prepare(ctx_id=-1, det_size=(640, 640))
print("Model ready.")


def decide_category_by_ratio(male_count, female_count, tie_toggle):
    """
    Audience-ratio based ad selection (mirrors the 'Audience Analysis' +
    'Ad Rotation' modules in the SRS):
      - majority gender in front of the camera right now wins
      - on an exact tie, alternate fairly between male/female instead of
        always favoring one
    Returns (category, updated_tie_toggle)
    """
    if male_count == 0 and female_count == 0:
        return "generic", tie_toggle
    if male_count > female_count:
        return "male", tie_toggle
    if female_count > male_count:
        return "female", tie_toggle
    return ("male" if tie_toggle else "female"), (not tie_toggle)


def load_ads(category):
    return sorted(glob.glob(os.path.join(ADS_DIR, category, "*.jpg")) +
                  glob.glob(os.path.join(ADS_DIR, category, "*.jpeg")) +
                  glob.glob(os.path.join(ADS_DIR, category, "*.png")))


AD_LIBRARY = {
    "male": load_ads("male"),
    "female": load_ads("female"),
    "generic": load_ads("generic"),
}

for cat, files in AD_LIBRARY.items():
    print(f"[ads] {cat}: {len(files)} image(s) loaded")
    if not files:
        print(f"  -> put at least one .jpg/.png in ads/{cat}/  (a placeholder will be shown otherwise)")


def make_placeholder(text):
    img = np.zeros((720, 1280, 3), dtype=np.uint8)
    cv2.putText(img, text, (60, 360), cv2.FONT_HERSHEY_SIMPLEX, 1.4, (255, 255, 255), 3)
    return img


def get_current_ad_frame(category, index):
    files = AD_LIBRARY.get(category) or []
    if not files:
        return make_placeholder(f"No ads found for: {category}")
    fname = files[index % len(files)]
    img = cv2.imread(fname)
    if img is None:
        return make_placeholder(f"Could not read: {fname}")
    return img


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
    cap.set(3, 640)
    cap.set(4, 480)

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

    cv2.namedWindow("Ads", cv2.WINDOW_NORMAL)
    fullscreen = True
    cv2.setWindowProperty("Ads", cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)

    current_category = "generic"
    last_face_seen = 0
    ad_index = 0
    last_ad_switch = 0
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

        faces = face_app.get(frame)

        if len(faces) > 0:
            last_face_seen = time.time()
            male_count = 0
            female_count = 0

            for f in faces:
                x1, y1, x2, y2 = f.bbox.astype(int)
                gender = "Male" if f.sex == "M" else "Female"
                age = int(f.age)
                counted = f.det_score >= DET_SCORE_THRESHOLD

                if counted:
                    if gender == "Male":
                        male_count += 1
                        box_color = (0, 0, 255)
                    else:
                        female_count += 1
                        box_color = (255, 0, 255)
                    label = f"{gender}, {age} ({f.det_score:.0%})"
                else:
                    box_color = (128, 128, 128)  # low-confidence detection -> shown but not counted
                    label = f"Uncertain ({f.det_score:.0%})"

                cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, 2)
                cv2.putText(frame, label, (x1, max(y1 - 10, 20)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

            current_category, tie_toggle = decide_category_by_ratio(male_count, female_count, tie_toggle)

            summary = f"Audience: {male_count} male, {female_count} female -> showing: {current_category}"
            cv2.putText(frame, summary, (10, frame.shape[0] - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 0), 1)
        else:
            if time.time() - last_face_seen > NO_FACE_TIMEOUT_SECONDS:
                current_category = "generic"

        cv2.imshow("Camera", frame)

        now = time.time()
        if now - last_ad_switch > AD_SWITCH_SECONDS:
            ad_index += 1
            last_ad_switch = now
        ad_frame = get_current_ad_frame(current_category, ad_index)
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
