# Laptop-Only Digital Signage (No Hardware Required)

This is a stripped-down, working version of the original project that runs
entirely on your laptop using the built-in webcam. It removes everything
that required extra hardware or paid services: Raspberry Pi, Arduino/NodeMCU
smart plug, MQTT, Firebase, and the Flutter mobile app.

## What's included
```
laptop_project/
├── signage_app.py          <- the whole app, one file
├── models/                 <- pre-trained detection models (already downloaded & verified working)
│   ├── deploy_age.prototxt
│   ├── deploy_gender.prototxt
│   ├── age_net.caffemodel
│   ├── gender_net.caffemodel
│   └── haarcascade_frontalface_default.xml
└── ads/
    ├── male/                <- ads shown when a male is detected
    ├── female/               <- ads shown when a female is detected
    └── generic/              <- ads shown when nobody is detected
```
Each `ads/` subfolder already has 1-2 placeholder sample images so the app
runs immediately. Replace them with your own `.jpg`/`.png` ad images —
just drop files into the matching folder, no code changes needed.

## Setup (one-time)

1. Install Python 3.8+ if you don't have it.
2. Install the one dependency:
   ```
   pip install opencv-python
   ```
   (that's it — no Firebase SDK, no Flutter, no MQTT libraries)

## Run it

```
python signage_app.py
```

Two windows will open:
- **Camera** — small debug window showing your webcam feed with a box around
  detected faces and the predicted age/gender.
- **Ads** — fullscreen window that rolls through the ad images matching
  whoever is currently in front of the camera. Falls back to `generic` ads
  after 6 seconds with nobody detected.

**Controls:** press `q` to quit, `f` to toggle fullscreen on the Ads window.

## What changed vs. the original repo (so it actually runs)

| Original problem | Fix applied here |
|---|---|
| `protoPathAge = os.path.sep.join([r"PATH", ...])` — literal placeholder, crashes immediately | Replaced with real relative paths using `os.path.join(MODEL_DIR, ...)` |
| `age_net.caffemodel` / `gender_net.caffemodel` weight files missing from repo | Downloaded the actual Levi & Hassner (2015) trained weights and verified they load correctly with the repo's own `.prototxt` files |
| Ad display logic lived in Raspberry Pi shell scripts + Firebase Firestore listener | Replaced with a simple in-process Python loop that picks images from local folders — no server, no internet needed |
| Required Raspberry Pi + HDMI display + Arduino smart plug | Runs on your laptop's own webcam + screen, nothing else |
| Required Firebase project + service account credentials | Removed entirely — no account, no API keys needed |
| Required Flutter mobile app to upload ads | Removed — just drop image files into `ads/male`, `ads/female`, `ads/generic` |
| `while cap.isOpened(): ... continue` busy-loops forever if no face is ever found, `break` only exits the inner `for` loop not the outer `while` | Rewritten with a clean single loop and a proper `q`-to-quit check every frame |

## Notes for your report / viva

- Face detection: Haar Cascade (`haarcascade_frontalface_default.xml`) — same
  lightweight method the original project used, chosen for speed over
  accuracy-heavier options like HOG+SVM or deep-learning detectors.
- Age/Gender prediction: Caffe model trained by Gil Levi & Tal Hassner (2015),
  the same pre-trained model referenced in the original repo. 8 age buckets,
  2 gender classes.
- This version demonstrates the **AI + ad-rolling logic** end-to-end on a
  single machine. If your report needs to show the "full" architecture
  (multi-device, cloud sync, remote power control), keep those as documented
  *future/hardware extensions* rather than things you need to implement to
  get a working demo.
