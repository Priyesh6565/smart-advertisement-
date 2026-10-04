"""
Lightweight Centroid & IoU Face Tracker with Demographic Temporal Smoothing
--------------------------------------------------------------------------
Assigns stable IDs to detected faces across frames and maintains an Exponential
Moving Average (EMA) of demographic probabilities (gender and age bracket).

Key Benefits:
- Eliminates single-frame "confident wrong" misclassifications (e.g. glare, extreme angles).
- Prevents 1-frame transient detections from triggering ad category switches.
- Produces a clean, persistent active audience count.
"""

import numpy as np


def compute_iou(box1, box2):
    """Computes Intersection-over-Union (IoU) between two bounding boxes [x1, y1, x2, y2]."""
    x1 = max(box1[0], box2[0])
    y1 = max(box1[1], box2[1])
    x2 = min(box1[2], box2[2])
    y2 = min(box1[3], box2[3])

    inter_w = max(0, x2 - x1)
    inter_h = max(0, y2 - y1)
    inter_area = inter_w * inter_h

    area1 = max(0, box1[2] - box1[0]) * max(0, box1[3] - box1[1])
    area2 = max(0, box2[2] - box2[0]) * max(0, box2[3] - box2[1])

    union_area = area1 + area2 - inter_area
    if union_area <= 0:
        return 0.0
    return inter_area / union_area


def compute_centroid_distance(box1, box2):
    """Euclidean distance between center points of two boxes."""
    c1_x = (box1[0] + box1[2]) / 2.0
    c1_y = (box1[1] + box1[3]) / 2.0
    c2_x = (box2[0] + box2[2]) / 2.0
    c2_y = (box2[1] + box2[3]) / 2.0
    return np.hypot(c1_x - c2_x, c1_y - c2_y)


class TrackedFace:
    """Represents a single person tracked over consecutive frames."""

    def __init__(self, track_id, bbox, gender_probs, age_probs, ema_alpha=0.25):
        self.track_id = track_id
        self.bbox = np.array(bbox, dtype=float)
        self.ema_alpha = ema_alpha

        # Smoothing probabilities with Exponential Moving Average (EMA)
        self.gender_probs = np.array(gender_probs, dtype=float)  # [p_male, p_female]
        self.age_probs = np.array(age_probs, dtype=float)        # [9 age bracket probabilities]

        self.hits = 1
        self.lost_frames = 0

    def update(self, bbox, gender_probs, age_probs):
        """Updates track with new detection and applies EMA to demographic probabilities."""
        # Smooth bbox (65% current, 35% new) to eliminate jitter
        self.bbox = 0.65 * self.bbox + 0.35 * np.array(bbox, dtype=float)

        # Exponential moving average for demographic probabilities
        self.gender_probs = (1.0 - self.ema_alpha) * self.gender_probs + self.ema_alpha * np.array(gender_probs)
        self.age_probs = (1.0 - self.ema_alpha) * self.age_probs + self.ema_alpha * np.array(age_probs)

        self.hits += 1
        self.lost_frames = 0

    def get_gender(self):
        """Returns ('Male' or 'Female', confidence_float)."""
        p_male, p_female = self.gender_probs[0], self.gender_probs[1]
        if p_male >= p_female:
            return "Male", float(p_male / (p_male + p_female))
        return "Female", float(p_female / (p_male + p_female))

    def get_age_bracket(self, age_labels):
        """Returns (best_bracket_string, confidence_float)."""
        idx = int(np.argmax(self.age_probs))
        conf = float(self.age_probs[idx] / np.sum(self.age_probs))
        return age_labels[idx], conf


class FaceTracker:
    """
    Manages active face tracks using dual IoU + Centroid distance matching.
    """

    def __init__(self, iou_threshold=0.3, max_lost_frames=18, min_hits_to_confirm=3, ema_alpha=0.25):
        self.iou_threshold = iou_threshold
        self.max_lost_frames = max_lost_frames
        self.min_hits_to_confirm = min_hits_to_confirm
        self.ema_alpha = ema_alpha

        self.tracks = {}  # track_id -> TrackedFace
        self.next_track_id = 1

    def update(self, detections):
        """
        detections: list of dicts with keys:
          - 'bbox': [x1, y1, x2, y2]
          - 'gender_probs': [p_male, p_female]
          - 'age_probs': [p0, p1, ..., p8]
        """
        matched_track_ids = set()
        unmatched_det_indices = list(range(len(detections)))

        if len(self.tracks) > 0 and len(detections) > 0:
            track_ids = list(self.tracks.keys())

            # Pass 1: Primary IoU Matching
            iou_matrix = np.zeros((len(track_ids), len(detections)), dtype=float)
            for i, tid in enumerate(track_ids):
                for j, det in enumerate(detections):
                    iou_matrix[i, j] = compute_iou(self.tracks[tid].bbox, det['bbox'])

            while True:
                max_val = np.max(iou_matrix)
                if max_val < self.iou_threshold:
                    break

                i, j = np.unravel_index(np.argmax(iou_matrix), iou_matrix.shape)
                tid = track_ids[i]

                self.tracks[tid].update(
                    detections[j]['bbox'],
                    detections[j]['gender_probs'],
                    detections[j]['age_probs']
                )

                matched_track_ids.add(tid)
                if j in unmatched_det_indices:
                    unmatched_det_indices.remove(j)

                iou_matrix[i, :] = -1.0
                iou_matrix[:, j] = -1.0

            # Pass 2: Secondary Centroid Distance Fallback (for rapid head motion)
            remaining_track_ids = [tid for tid in track_ids if tid not in matched_track_ids]
            if remaining_track_ids and unmatched_det_indices:
                for tid in remaining_track_ids:
                    t_box = self.tracks[tid].bbox
                    box_dim = max(t_box[2] - t_box[0], t_box[3] - t_box[1])
                    max_dist = max(50.0, box_dim * 1.25)

                    best_dist = float("inf")
                    best_j = None
                    for j in unmatched_det_indices:
                        dist = compute_centroid_distance(t_box, detections[j]['bbox'])
                        if dist < max_dist and dist < best_dist:
                            best_dist = dist
                            best_j = j

                    if best_j is not None:
                        self.tracks[tid].update(
                            detections[best_j]['bbox'],
                            detections[best_j]['gender_probs'],
                            detections[best_j]['age_probs']
                        )
                        matched_track_ids.add(tid)
                        unmatched_det_indices.remove(best_j)

        # Increment lost counter for unmatched tracks
        for tid in list(self.tracks.keys()):
            if tid not in matched_track_ids:
                self.tracks[tid].lost_frames += 1
                if self.tracks[tid].lost_frames > self.max_lost_frames:
                    del self.tracks[tid]

        # Spawn new tracks for unmatched detections
        for idx in unmatched_det_indices:
            det = detections[idx]
            new_track = TrackedFace(
                track_id=self.next_track_id,
                bbox=det['bbox'],
                gender_probs=det['gender_probs'],
                age_probs=det['age_probs'],
                ema_alpha=self.ema_alpha
            )
            self.tracks[self.next_track_id] = new_track
            self.next_track_id += 1

    def get_confirmed_tracks(self):
        """Returns tracks that have survived long enough to be confirmed as real audience."""
        return [
            t for t in self.tracks.values()
            if t.hits >= self.min_hits_to_confirm and t.lost_frames == 0
        ]
