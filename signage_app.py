"""
Laptop-only Digital Signage: Age/Gender Detection + Targeted Ad Slideshow
--------------------------------------------------------------------------
Runs entirely on your laptop using the built-in webcam. No Firebase,
Flutter, MQTT, or Raspberry Pi hardware needed.

Two windows:
  - "Camera" : debug window showing every detected face + predicted age/gender,
               plus a running male/female audience count at the bottom
  - "Ads"    : fullscreen window that rolls advertisement images based on
               the MAJORITY gender currently in front of the camera
               (e.g. 3 men + 1 woman -> male ads; exact ties alternate fairly)

Controls:
  q  -> quit
  f  -> toggle fullscreen on the Ads window

Folder layout expected (already created for you):
  models/deploy_age.prototxt
  models/deploy_gender.prototxt
  models/age_net.caffemodel
  models/gender_net.caffemodel
  models/face_detector_deploy.prototxt
  models/res10_300x300_ssd_iter_140000.caffemodel
  ads/male/*.jpg or *.png
  ads/female/*.jpg or *.png
  ads/generic/*.jpg or *.png
"""

import cv2
import numpy as np
import os
import time
import glob

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, "models")
ADS_DIR = os.path.join(BASE_DIR, "ads")

# ---- Model paths (FIXED: no more literal "PATH" placeholders) ----
PROTO_AGE = os.path.join(MODEL_DIR, "deploy_age.prototxt")
MODEL_AGE = os.path.join(MODEL_DIR, "age_net.caffemodel")
PROTO_GENDER = os.path.join(MODEL_DIR, "deploy_gender.prototxt")
MODEL_GENDER = os.path.join(MODEL_DIR, "gender_net.caffemodel")
# DNN-based face detector (SSD/ResNet10) -- far more reliable than Haar
# cascades for multiple people, side angles, and varied lighting, which
# matters a lot once you're detecting a *group* rather than one face.
PROTO_FACE = os.path.join(MODEL_DIR, "face_detector_deploy.prototxt")
MODEL_FACE = os.path.join(MODEL_DIR, "res10_300x300_ssd_iter_140000.caffemodel")

FACE_CONFIDENCE_THRESHOLD = 0.5  # lower (e.g. 0.4) if faces at the edges of frame are being missed

MODEL_MEAN_VALUES = (78.4263377603, 87.7689143744, 114.895847746)
AGE_LIST = ['(0, 2)', '(4, 6)', '(8, 12)', '(15, 20)', '(25, 32)', '(38, 43)', '(48, 53)', '(60, 100)']
GENDER_LIST = ['Male', 'Female']

AD_SWITCH_SECONDS = 4          # how long each ad image stays on screen
NO_FACE_TIMEOUT_SECONDS = 2    # fall back to generic ads if nobody detected

for path, name in [(PROTO_AGE, "deploy_age.prototxt"), (MODEL_AGE, "age_net.caffemodel"),
                    (PROTO_GENDER, "deploy_gender.prototxt"), (MODEL_GENDER, "gender_net.caffemodel"),
                    (PROTO_FACE, "face_detector_deploy.prototxt"),
                    (MODEL_FACE, "res10_300x300_ssd_iter_140000.caffemodel")]:
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing required model file: {name} (expected at {path})")

age_net = cv2.dnn.readNetFromCaffe(PROTO_AGE, MODEL_AGE)
gender_net = cv2.dnn.readNetFromCaffe(PROTO_GENDER, MODEL_GENDER)
face_net = cv2.dnn.readNetFromCaffe(PROTO_FACE, MODEL_FACE)


def detect_faces(frame):
    """
    Returns a list of (x, y, w, h) boxes for every face detected above
    FACE_CONFIDENCE_THRESHOLD, clipped to stay inside the frame.
    """
    h, w = frame.shape[:2]
    blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300),
                                  (104.0, 177.0, 123.0))
    face_net.setInput(blob)
    detections = face_net.forward()

    boxes = []
    for i in range(detections.shape[2]):
        confidence = detections[0, 0, i, 2]
        if confidence < FACE_CONFIDENCE_THRESHOLD:
            continue
        box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
        x1, y1, x2, y2 = box.astype(int)
        x1, y1 = max(x1, 0), max(y1, 0)
        x2, y2 = min(x2, w), min(y2, h)
        if x2 > x1 and y2 > y1:
            boxes.append((x1, y1, x2 - x1, y2 - y1))
    return boxes


def load_ads(category):
    files = sorted(glob.glob(os.path.join(ADS_DIR, category, "*.jpg")) +
                    glob.glob(os.path.join(ADS_DIR, category, "*.jpeg")) +
                    glob.glob(os.path.join(ADS_DIR, category, "*.png")))
    return files


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


def predict_age_gender(face_img):
    blob = cv2.dnn.blobFromImage(face_img, 1, (227, 227), MODEL_MEAN_VALUES, swapRB=False)
    gender_net.setInput(blob)
    gender = GENDER_LIST[gender_net.forward()[0].argmax()]
    age_net.setInput(blob)
    age = AGE_LIST[age_net.forward()[0].argmax()]
    return age, gender


def decide_category_by_ratio(male_count, female_count, tie_toggle):
    """
    Audience-ratio based ad selection (mirrors the 'Audience Analysis' +
    'Ad Rotation' modules in the SRS):
      - majority gender in front of the camera right now wins
      - on an exact tie, alternate fairly between male/female each time
        this function is called with a tie, instead of always favoring one
    Returns (category, updated_tie_toggle)
    """
    if male_count == 0 and female_count == 0:
        return "generic", tie_toggle
    if male_count > female_count:
        return "male", tie_toggle
    if female_count > male_count:
        return "female", tie_toggle
    # exact tie -> round-robin fairness instead of always picking the same one
    return ("male" if tie_toggle else "female"), (not tie_toggle)


def main():
    # On macOS, explicitly request the AVFoundation backend -- this is what
    # actually triggers the camera permission prompt reliably. Falls back to
    # the default backend on other platforms.
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

    # The camera can report "opened" successfully even before macOS grants
    # permission -- the first several reads may fail while the permission
    # prompt is pending. Give it a few tries before giving up entirely.
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
            if consecutive_failures > 30:  # ~1 second of failures at 30fps
                print("Webcam stopped returning frames. Exiting.")
                break
            continue
        consecutive_failures = 0

        # DNN-based detection: much better than Haar cascades at picking up
        # multiple people, side angles, and varied lighting -- important
        # now that we're analyzing a whole group, not just one face.
        faces = detect_faces(frame)

        if len(faces) > 0:
            last_face_seen = time.time()
            male_count = 0
            female_count = 0

            for (x, y, w, h) in faces:
                face_img = frame[y:y + h, x:x + w].copy()
                age, gender = predict_age_gender(face_img)
                if gender == "Male":
                    male_count += 1
                else:
                    female_count += 1

                cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 0, 255), 2)
                cv2.putText(frame, f"{gender}, {age}", (x, max(y - 10, 20)),
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
