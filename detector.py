"""
Unified Real-time Face Detector
--------------------------------
Provides high-performance face and 5-point landmark detection on CPU.
Supports:
1. InsightFace SCRFD (when buffalo_l or buffalo_s model is present)
2. OpenCV YuNet ONNX (ultra-lightweight 230KB model, 60+ FPS on CPU, zero download wait)
"""

import os
import cv2
import numpy as np


class DetectedFace:
    """Standardized face detection output across all backends."""

    def __init__(self, bbox, det_score, kps=None):
        self.bbox = np.array(bbox, dtype=int)  # [x1, y1, x2, y2]
        self.det_score = float(det_score)
        self.kps = np.array(kps) if kps is not None else None


class UnifiedFaceDetector:

    def __init__(self, yunet_path=None, prefer_insightface=True, backend="auto"):
        self.backend = None
        self.detector = None
        if yunet_path is None:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            yunet_path = os.path.join(base_dir, "models", "face_detection_yunet.onnx")
        self.yunet_path = yunet_path

        backend_lower = (backend or "auto").lower()

        # 1. Try InsightFace if requested or preferred
        if backend_lower in ("auto", "insightface") and (prefer_insightface or backend_lower == "insightface"):
            try:
                # Check if buffalo_l or buffalo_s is already downloaded
                home = os.path.expanduser("~")
                insight_dir = os.path.join(home, ".insightface", "models")
                has_cached_buffalo = os.path.exists(os.path.join(insight_dir, "buffalo_l")) or \
                                     os.path.exists(os.path.join(insight_dir, "buffalo_s"))

                if has_cached_buffalo or backend_lower == "insightface":
                    from insightface.app import FaceAnalysis
                    print("[Detector] Initializing InsightFace SCRFD...")
                    face_app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection"], providers=["CPUExecutionProvider"])
                    face_app.prepare(ctx_id=-1, det_size=(640, 640))
                    self.detector = face_app
                    self.backend = "insightface"
                    print("[Detector] InsightFace SCRFD loaded successfully.")
            except Exception as e:
                print(f"[Detector] InsightFace initialization skipped: {e}")

        # 2. Fall back to or explicitly use OpenCV YuNet
        if self.detector is None and backend_lower in ("auto", "yunet") and os.path.exists(self.yunet_path):
            try:
                print(f"[Detector] Initializing ultra-fast OpenCV YuNet detector from {self.yunet_path}...")
                self.detector = cv2.FaceDetectorYN.create(self.yunet_path, "", (640, 640))
                self.backend = "yunet"
                self.current_input_size = (640, 640)
                print("[Detector] OpenCV YuNet loaded successfully.")
            except Exception as e:
                print(f"[Detector] YuNet initialization error: {e}")

        # 3. If neither worked, try standard InsightFace prepare (may trigger download)
        if self.detector is None:
            try:
                from insightface.app import FaceAnalysis
                print("[Detector] Loading InsightFace (downloading if not cached)...")
                face_app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection"], providers=["CPUExecutionProvider"])
                face_app.prepare(ctx_id=-1, det_size=(640, 640))
                self.detector = face_app
                self.backend = "insightface"
            except Exception as e:
                raise RuntimeError(f"Failed to initialize any face detector (InsightFace / YuNet): {e}")

    def detect(self, frame):
        """
        Detects faces in frame.
        Returns: list of DetectedFace objects with bbox [x1, y1, x2, y2], det_score, and kps.
        """
        h, w = frame.shape[:2]
        results = []

        if self.backend == "insightface":
            raw_faces = self.detector.get(frame)
            for f in raw_faces:
                bbox = f.bbox.astype(int)
                det_score = getattr(f, "det_score", 1.0)
                kps = getattr(f, "kps", None)
                results.append(DetectedFace(bbox, det_score, kps))

        elif self.backend == "yunet":
            # Adjust input size if frame dimension changed
            if self.current_input_size != (w, h):
                self.detector.setInputSize((w, h))
                self.current_input_size = (w, h)

            _, faces = self.detector.detect(frame)
            if faces is not None:
                for f in faces:
                    x, y, box_w, box_h = f[0:4]
                    x1 = max(0, int(x))
                    y1 = max(0, int(y))
                    x2 = min(w, int(x + box_w))
                    y2 = min(h, int(y + box_h))
                    det_score = float(f[14])
                    # Landmarks: right_eye, left_eye, nose, right_mouth, left_mouth
                    kps = [
                        [f[4], f[5]],    # right eye
                        [f[6], f[7]],    # left eye
                        [f[8], f[9]],    # nose
                        [f[10], f[11]],  # right mouth
                        [f[12], f[13]],  # left mouth
                    ]
                    results.append(DetectedFace([x1, y1, x2, y2], det_score, kps))

        return results

    # Alias to match InsightFace's API
    get = detect
