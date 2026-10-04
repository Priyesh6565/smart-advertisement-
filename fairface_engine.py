"""
FairFace Demographic Engine for Age, Gender, and Race Classification
---------------------------------------------------------------------
Uses FairFace (CVPR 2021) trained on 108k ethnically-balanced images,
with 15,000+ curated Indian faces across all age brackets.

Features:
- Dual execution backend: Uses onnxruntime if installed, or cv2.dnn as zero-dependency fallback.
- Standard 0.25 margin face crop preprocessing (matches FairFace training distribution).
- Direct classification into 9 discrete age brackets + mapping to ad marketing categories:
  'kids' (0-9), 'teens' (10-19), 'adults' (20-49), 'seniors' (50+).
"""

import os
import cv2
import numpy as np

FAIRFACE_AGES = ['0-2', '3-9', '10-19', '20-29', '30-39', '40-49', '50-59', '60-69', '70+']
FAIRFACE_GENDERS = ['Male', 'Female']
FAIRFACE_RACES = ['White', 'Black', 'Latino_Hispanic', 'East Asian', 'Southeast Asian', 'Indian', 'Middle Eastern']

AGE_CATEGORY_MAPPING = {
    '0-2': 'kids',
    '3-9': 'kids',
    '10-19': 'teens',
    '20-29': 'adults',
    '30-39': 'adults',
    '40-49': 'adults',
    '50-59': 'seniors',
    '60-69': 'seniors',
    '70+': 'seniors',
}


def map_bracket_to_category(bracket):
    """Maps FairFace's 9 age classes to high-level ad marketing folders."""
    return AGE_CATEGORY_MAPPING.get(bracket, 'adults')


def softmax(x):
    """Numerically stable softmax."""
    e_x = np.exp(x - np.max(x))
    return e_x / e_x.sum(axis=-1, keepdims=True)


class FairFaceEngine:
    def __init__(self, model_path=None):
        if model_path is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            model_path = os.path.join(base_dir, "models", "fairface.onnx")

        if not os.path.exists(model_path):
            raise FileNotFoundError(f"FairFace model not found at {model_path}")

        self.model_path = model_path
        self.backend = None
        self.session = None
        self.net = None

        # Try onnxruntime first, fall back to cv2.dnn
        try:
            import onnxruntime as ort
            # Use CPU execution provider
            self.session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
            self.input_name = self.session.get_inputs()[0].name
            self.backend = "onnxruntime"
            print(f"[FairFaceEngine] Loaded {model_path} via ONNXRuntime (CPU)")
        except ImportError:
            try:
                self.net = cv2.dnn.readNetFromONNX(model_path)
                self.backend = "cv2.dnn"
                print(f"[FairFaceEngine] Loaded {model_path} via OpenCV DNN")
            except Exception as e:
                raise RuntimeError(f"Could not load FairFace ONNX model with either onnxruntime or cv2.dnn: {e}")

    def preprocess(self, frame, bbox):
        """
        Crops face bbox with 0.25 margin padding (required by FairFace model),
        resizes to 224x224, and applies ImageNet normalization.
        Handles frame boundaries gracefully with border replication.
        """
        h_img, w_img = frame.shape[:2]
        x1, y1, x2, y2 = bbox
        w = max(0, x2 - x1)
        h = max(0, y2 - y1)

        if w < 10 or h < 10:
            return None

        # 0.25 margin padding
        pad_w = int(w * 0.25)
        pad_h = int(h * 0.25)
        x_start = x1 - pad_w
        y_start = y1 - pad_h
        x_end = x2 + pad_w
        y_end = y2 + pad_h

        # In-bounds slice
        src_x1 = max(0, x_start)
        src_y1 = max(0, y_start)
        src_x2 = min(w_img, x_end)
        src_y2 = min(h_img, y_end)

        if src_x2 <= src_x1 or src_y2 <= src_y1:
            return None

        crop = frame[src_y1:src_y2, src_x1:src_x2]
        if crop.size == 0:
            return None

        # If any side exceeded frame bounds, pad with border replicate to preserve natural proportions
        pad_top = max(0, src_y1 - y_start)
        pad_bottom = max(0, y_end - src_y2)
        pad_left = max(0, src_x1 - x_start)
        pad_right = max(0, x_end - src_x2)

        if pad_top > 0 or pad_bottom > 0 or pad_left > 0 or pad_right > 0:
            crop = cv2.copyMakeBorder(crop, pad_top, pad_bottom, pad_left, pad_right, cv2.BORDER_REPLICATE)

        # Resize to 224x224
        resized = cv2.resize(crop, (224, 224), interpolation=cv2.INTER_AREA)

        # Convert to RGB and normalize (ImageNet mean & std)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        normalized = (rgb - mean) / std

        # Transpose to NCHW: (1, 3, 224, 224)
        blob = np.transpose(normalized, (2, 0, 1))
        blob = np.expand_dims(blob, axis=0)
        return blob

    def predict(self, frame, bbox):
        """
        Runs demographic inference.
        Returns:
            dict containing:
              - 'gender_probs': [p_male, p_female]
              - 'age_probs': [p0, p1, ..., p8]
              - 'race_probs': [p0, ..., p6]
              - 'gender': 'Male' or 'Female'
              - 'gender_conf': float (0.0 to 1.0)
              - 'age_bracket': str (e.g. '20-29')
              - 'age_category': str ('kids', 'teens', 'adults', 'seniors')
              - 'race': str (e.g. 'Indian')
        """
        blob = self.preprocess(frame, bbox)
        if blob is None:
            return None

        if self.backend == "onnxruntime":
            outputs = self.session.run(None, {self.input_name: blob})
            # Outputs in yakhyo/fairface-onnx:
            # outputs[0]: race logits (shape [1, 7])
            # outputs[1]: gender logits (shape [1, 2])
            # outputs[2]: age logits (shape [1, 9])
            race_logits = outputs[0][0]
            gender_logits = outputs[1][0]
            age_logits = outputs[2][0]
        else:
            self.net.setInput(blob)
            # OpenCV DNN forward
            out_names = self.net.getUnconnectedOutLayersNames()
            outputs = self.net.forward(out_names)
            race_logits = outputs[0][0]
            gender_logits = outputs[1][0]
            age_logits = outputs[2][0]

        gender_probs = softmax(gender_logits)
        age_probs = softmax(age_logits)
        race_probs = softmax(race_logits)

        gender_idx = int(np.argmax(gender_probs))
        age_idx = int(np.argmax(age_probs))
        race_idx = int(np.argmax(race_probs))

        gender = FAIRFACE_GENDERS[gender_idx]
        gender_conf = float(gender_probs[gender_idx])
        age_bracket = FAIRFACE_AGES[age_idx]
        age_category = map_bracket_to_category(age_bracket)
        race = FAIRFACE_RACES[race_idx]

        return {
            'gender_probs': gender_probs,
            'age_probs': age_probs,
            'race_probs': race_probs,
            'gender': gender,
            'gender_conf': gender_conf,
            'age_bracket': age_bracket,
            'age_category': age_category,
            'race': race,
        }
