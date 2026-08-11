# Laptop-Only Digital Signage (No Hardware Required)

Runs entirely on your laptop using the built-in webcam. No Raspberry Pi,
Arduino/NodeMCU, MQTT, Firebase, or Flutter app needed.

## Setup (one-time)
```
pip install opencv-python
```

## Run it
```
python signage_app.py
```
Two windows open: **Camera** (debug view with face boxes + predicted age/gender/confidence)
and **Ads** (fullscreen, rolls ads based on majority gender detected).
Press `q` to quit, `f` to toggle fullscreen.

Drop your own `.jpg`/`.png` ad images into `ads/male/`, `ads/female/`, `ads/generic/` —
no code changes needed.

## How ad selection works (group / multi-person support)
Every frame, the app detects **all** faces (not just one), classifies each,
and picks ads by majority:
- 6 male + 4 female detected -> male ads
- exact tie -> alternates fairly between male/female each time, rather than
  always favoring one gender (mirrors the "fair rotation" idea in the SRS)
- nobody detected for 2+ seconds -> falls back to `generic` ads

## Key fixes applied vs. the original repo / earlier versions

| Problem | Fix |
|---|---|
| `PATH` placeholder in original repo's paths | Real relative paths |
| Missing `.caffemodel` weight files | Downloaded verified Levi & Hassner (2015) weights |
| Haar cascade missed/misdetected faces in group shots (angled poses) | Replaced with OpenCV's DNN SSD face detector (`res10_300x300`) |
| **Tight face crop caused wrong gender predictions on side angles / tied-back hair** | Pad each face crop by 30% before classifying — the Adience-trained model expects a looser crop than a tight bounding box, and tight crops measurably hurt accuracy (verified: a real test face flipped from "Female, 100% confidence, wrong" to "Male, 99% confidence, correct" after padding) |
| Model would confidently force a guess even on ambiguous faces | Added a confidence threshold (65%) — low-confidence calls are labeled "Uncertain" and excluded from the male/female count entirely, instead of skewing the ad decision |
| Required Raspberry Pi, Arduino smart plug, MQTT, Firebase, Flutter app | All removed — everything runs in this one Python file on your laptop |

## Known limitations (good to mention in your report/viva)
- The age/gender model is trained on the **Adience dataset** (Gil Levi & Tal
  Hassner, 2015 — ~26,000 unfiltered Flickr photos of 2,284 people). It's a
  well-known academic benchmark but small and not very diverse by modern
  standards, so accuracy drops on extreme angles, unusual hairstyles/accessories,
  and poor lighting — this is a property of the trained weights themselves, not
  something fixable by changing inference-time parameters.
- The `.caffemodel` weights are frozen; genuinely improving accuracy further
  would require **fine-tuning on new labeled data** (a real training pipeline,
  out of scope for a laptop demo) rather than parameter tweaking.
- Practical mitigations already applied: padded face crops (see above) and
  confidence-based "Uncertain" filtering. A further optional improvement
  (not implemented here) would be temporal smoothing — averaging predictions
  for the same person across several frames — which helps when a single frame
  catches a bad angle but the person is otherwise facing the camera normally.
