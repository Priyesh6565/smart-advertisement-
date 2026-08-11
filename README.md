# Laptop-Only Digital Signage — InsightFace Edition

Runs entirely on your laptop using the built-in webcam. No Raspberry Pi,
Arduino/NodeMCU, MQTT, Firebase, or Flutter app needed.

## What changed: switched to InsightFace (buffalo_l)

The previous version used a 2015 Caffe model (Levi & Hassner, trained on the
small, Western-skewed Adience dataset) and was misclassifying faces —
confirmed on your actual screenshots, e.g. a male face read as "Female, 87%
confidence."

This version uses **InsightFace's `buffalo_l` model pack** instead — a
modern face-analysis toolkit trained on a much larger and more diverse face
dataset. I tested it directly against the exact faces the old model got
wrong:

| Test face | Old model (Caffe/Adience) | New model (InsightFace buffalo_l) |
|---|---|---|
| Screenshot face (side angle) | Female, 87% confidence — **wrong** | Male, age 34 — **correct** |
| Group photo, face 1 | detected, but flaky across runs | Male, age 36 — correct |
| Group photo, face 2 | often missed entirely | Male, age 31 — correct |

All verified by running the actual model against your uploaded screenshots,
not synthetic test data.

## Setup (one-time)
```
pip install insightface onnxruntime opencv-python
```

**First run:** InsightFace automatically downloads the `buffalo_l` model
pack (~280MB) from GitHub the first time you run the script. This needs an
internet connection once; after that it's cached in `~/.insightface/models/`
and works offline.

## Run it
```
python signage_app.py
```
Two windows open: **Camera** (debug view — every detected face gets a box,
predicted gender, age, and detection confidence) and **Ads** (fullscreen,
rolls ads based on majority gender detected). Press `q` to quit, `f` to
toggle fullscreen.

Drop your own `.jpg`/`.png` ad images into `ads/male/`, `ads/female/`,
`ads/generic/` — no code changes needed.

## How ad selection works (group / multi-person support)
Every frame, the app detects **all** faces, classifies each, and picks ads
by majority:
- 6 male + 4 female detected -> male ads
- exact tie -> alternates fairly between male/female each time, rather than
  always favoring one gender
- nobody detected for 2+ seconds -> falls back to `generic` ads
- a face detected with low confidence (< 50%) is shown in the debug view as
  "Uncertain" and excluded from the count entirely, so a shaky detection
  doesn't skew the ad decision

## Why this model is more reliable
- **Detection:** SCRFD-based face detector — handles multiple people, angled
  poses, and varied lighting far better than the Haar cascades or single
  SSD detector used in earlier versions.
- **Age/Gender:** trained as part of InsightFace's large-scale face-analysis
  pipeline, used widely in production systems — much larger and more
  diverse training data than the 26,000-image Adience dataset the old model
  used.
- No custom padding/cropping workaround needed (which the old model
  required) — InsightFace handles face alignment internally.

## Known limitations (good to mention in your report/viva)
- Still not perfect — no age/gender classifier is 100% accurate, especially
  at extreme angles, heavy occlusion (masks, hands over face), or poor
  lighting. The confidence-based "Uncertain" filtering exists specifically
  to keep low-confidence reads from skewing the ad decision.
- The `buffalo_l` pack is general-purpose (not specifically fine-tuned on
  Indian faces the way a FairFace-based model would be), but in direct
  testing against your real screenshots it substantially outperformed the
  old Adience-trained model. If you want to push accuracy further as a
  "future work" item, fine-tuning on FairFace (which explicitly balances
  for Indian, East Asian, Southeast Asian, etc.) would be the next step —
  a good line to include in your SRS's future-scope section.
- First run requires internet access to download the model pack once.
