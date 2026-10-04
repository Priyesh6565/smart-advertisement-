# AI-Powered Audience-Targeted Digital Signage System

An intelligent, real-time digital signage and advertisement targeting system designed for laptop webcam environments, optimized specifically for **high accuracy on Indian demographics**.

---

## Key Technical Enhancements

### 1. FairFace Demographic Engine (Balanced on Indian Faces)
- **Problem Solved**: Off-the-shelf Western/East-Asian models (such as Caffe Adience or default InsightFace attribute heads) frequently misclassify Indian facial features, skin undertones, facial hair, and hair grooming styles.
- **Solution**: Integrates **FairFace (CVPR 2021)**, an academic deep learning model explicitly trained on a 108,501-image race-balanced dataset with **15,000+ curated Indian faces**.
- **Discrete Age Classification**: Replaces erratic continuous regression scalars with 9 marketing age brackets (`0-2`, `3-9`, `10-19`, `20-29`, `30-39`, `40-49`, `50-59`, `60-69`, `70+`), cleanly mapped to `kids`, `teens`, `adults`, and `seniors`.

### 2. Person-Level IoU Tracking + Temporal Probability Smoothing (EMA)
- **Problem Solved**: A single bad frame (e.g. 50° off-angle pose or severe screen glare) can produce a high-confidence misclassification that abruptly flips the displayed ad.
- **Solution**: The `FaceTracker` tracks individual people across frames. Each person maintains an **Exponential Moving Average (EMA)** of their demographic probabilities. A momentary glare frame is smoothed out by the person's sustained history without flipping the decision.

### 3. Decoupled, Paced Video Ad Player
- **Problem Solved**: Standard `cv2.VideoCapture.read()` decodes as fast as the loop runs, causing ads to play in slow-motion when detection is heavy, or fast-forward when the room is empty.
- **Solution**: `TargetedAdPlayer` enforces native 25/30 FPS playback using wall-clock synchronization.

### 4. Hierarchical Fallback Content Structure
Ads are resolved with automatic fallback search:
```
ads/<gender>/<age_bracket>/  -->  ads/<gender>/  -->  ads/generic/
```
If an ad for `ads/male/teens/` does not exist, it falls back to `ads/male/`, and then to `ads/generic/`.

---

## Directory Structure

```
├── ads/
│   ├── female/
│   │   ├── adults/
│   │   ├── kids/
│   │   ├── seniors/
│   │   └── teens/
│   ├── generic/
│   └── male/
│       ├── adults/
│       ├── kids/
│       ├── seniors/
│       └── teens/
├── models/
│   └── fairface.onnx
├── ad_manager.py       # Paced video playback & folder hierarchy
├── fairface_engine.py  # FairFace ONNX / OpenCV-DNN inference engine
├── tracker.py          # Person tracking & EMA probability smoothing
├── signage_app.py      # Main application pipeline & webcam interface
└── test_pipeline.py    # Test suite for tracker, ad player, & demographics
```

---

## Installation & Setup

1. **Install dependencies**:
   ```bash
   pip install opencv-python onnxruntime insightface numpy
   ```

2. **Run the Application**:
   - **Default webcam mode**:
     ```bash
     python signage_app.py
     ```
   - **Select specific camera index** (e.g. external USB camera or secondary webcam):
     ```bash
     python signage_app.py --source 1
     ```
   - **Simulation / Mock mode** (cycles through demo audience scenarios without webcam):
     ```bash
     python signage_app.py --mock
     ```
   - **Choose face detector backend** (`insightface` for highest landmark accuracy, `yunet` for ultra-fast 30+ FPS CPU execution):
     ```bash
     python signage_app.py --detector yunet
     ```
   - **Start directly in Fullscreen**:
     ```bash
     python signage_app.py --fullscreen
     ```

3. **Run Test Suite**:
   ```bash
   python test_pipeline.py
   ```

4. **Controls**:
   - `q`: Quit the application cleanly.
   - `f`: Toggle fullscreen mode for the Ads Display window.
   - Window Close (`X`): Automatically stops camera and cleans up resources.

