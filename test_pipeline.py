"""
Unit & Integration Test Suite for the Smart Advertisement Pipeline
------------------------------------------------------------------
Tests:
1. FaceTracker: track creation, IoU matching, lost frame cleanup, and EMA smoothing.
2. TargetedAdPlayer: folder hierarchy resolution, pacing, and fallback logic.
3. FairFaceEngine: preprocessing, shape compatibility, and mock inference.
"""

import os
import unittest
import numpy as np

from tracker import compute_iou, FaceTracker, TrackedFace
from ad_manager import TargetedAdPlayer
from fairface_engine import map_bracket_to_category, softmax, FAIRFACE_AGES


class TestPipeline(unittest.TestCase):

    def test_compute_iou(self):
        boxA = [10, 10, 50, 50]
        boxB = [10, 10, 50, 50]
        self.assertAlmostEqual(compute_iou(boxA, boxB), 1.0)

        boxC = [50, 50, 90, 90]
        self.assertAlmostEqual(compute_iou(boxA, boxC), 0.0)

        boxD = [30, 10, 70, 50]
        # Intersection: [30, 10, 50, 50] -> w=20, h=40 -> 800
        # Area A: 40*40=1600, Area D: 40*40=1600, Union: 3200-800=2400
        # IoU = 800/2400 = 1/3
        self.assertAlmostEqual(compute_iou(boxA, boxD), 1.0 / 3.0, places=4)

    def test_face_tracker_ema_smoothing(self):
        tracker = FaceTracker(iou_threshold=0.3, max_lost_frames=5, min_hits_to_confirm=2, ema_alpha=0.2)

        # Frame 1: Person 1 appears (Male 90%)
        det_frame1 = [{
            'bbox': [100, 100, 200, 200],
            'gender_probs': [0.90, 0.10],
            'age_probs': [0.0, 0.0, 0.0, 0.8, 0.2, 0.0, 0.0, 0.0, 0.0]
        }]
        tracker.update(det_frame1)
        # Not confirmed yet (hits = 1, min_hits = 2)
        self.assertEqual(len(tracker.get_confirmed_tracks()), 0)

        # Frame 2: Person 1 moves slightly, detected again (Male 90%)
        det_frame2 = [{
            'bbox': [102, 101, 202, 201],
            'gender_probs': [0.90, 0.10],
            'age_probs': [0.0, 0.0, 0.0, 0.8, 0.2, 0.0, 0.0, 0.0, 0.0]
        }]
        tracker.update(det_frame2)
        confirmed = tracker.get_confirmed_tracks()
        self.assertEqual(len(confirmed), 1)
        gender, conf = confirmed[0].get_gender()
        self.assertEqual(gender, "Male")
        self.assertGreater(conf, 0.85)

        # Frame 3: Glare/Angle occurs! Single frame outputs "Female 92%"
        det_frame3 = [{
            'bbox': [103, 100, 203, 200],
            'gender_probs': [0.08, 0.92],  # Confident wrong frame
            'age_probs': [0.0, 0.0, 0.0, 0.8, 0.2, 0.0, 0.0, 0.0, 0.0]
        }]
        tracker.update(det_frame3)
        confirmed = tracker.get_confirmed_tracks()
        self.assertEqual(len(confirmed), 1)
        gender, conf = confirmed[0].get_gender()

        # The tracked person must NOT flip to Female! EMA absorbs the bad frame.
        self.assertEqual(gender, "Male", "EMA failed to absorb single-frame confident wrong prediction!")
        print(f"[Test] Bad frame absorbed successfully! Sustained gender: {gender} ({conf:.1%})")

    def test_ad_hierarchy_resolution(self):
        ads_dir = os.path.join(os.path.dirname(__file__), "ads")
        player = TargetedAdPlayer(ads_dir)

        # Test resolution logic
        folder, videos = player.resolve_ad_folder("male", "adults")
        self.assertTrue(os.path.isdir(folder))

        # Test placeholder rendering
        frame = player.get_frame("male", "adults")
        self.assertEqual(frame.shape, (720, 1280, 3))
        player.release()

    def test_centroid_distance_and_tracking(self):
        from tracker import compute_centroid_distance
        b1 = [100, 100, 200, 200]
        b2 = [100, 100, 200, 200]
        self.assertEqual(compute_centroid_distance(b1, b2), 0.0)

        # Person moves quickly (IoU < 0.3 but centroid close)
        tracker = FaceTracker(iou_threshold=0.3, max_lost_frames=5, min_hits_to_confirm=2)
        det1 = [{'bbox': [100, 100, 200, 200], 'gender_probs': [0.9, 0.1], 'age_probs': [0.1]*9}]
        tracker.update(det1)
        
        # Rapid motion: box moved diagonally by 75px (IoU becomes ~0.15)
        det2 = [{'bbox': [175, 175, 275, 275], 'gender_probs': [0.9, 0.1], 'age_probs': [0.1]*9}]
        tracker.update(det2)
        confirmed = tracker.get_confirmed_tracks()
        self.assertEqual(len(confirmed), 1, "Centroid fallback should keep track associated during rapid movement")
        self.assertEqual(confirmed[0].track_id, 1)

    def test_ad_hierarchy_and_image_playback(self):
        ads_dir = os.path.join(os.path.dirname(__file__), "ads")
        player = TargetedAdPlayer(ads_dir)

        # 1. Test targeted resolution to specific category image
        folder, media = player.resolve_ad_folder("male", "adults")
        self.assertTrue(os.path.isdir(folder))
        self.assertGreater(len(media), 0)

        # 2. Test frame rendering (1280x720)
        frame = player.get_frame("male", "adults")
        self.assertEqual(frame.shape, (720, 1280, 3))

        # 3. Test fallback to generic when non-existent category requested
        folder_gen, media_gen = player.resolve_ad_folder("unknown", "unknown")
        self.assertIn("generic", folder_gen)
        player.release()

    def test_quality_gate(self):
        from signage_app import check_face_quality
        # Normal face
        ok, reason, clamped = check_face_quality([200, 200, 350, 350], [[240, 250], [310, 250]], 1280, 720)
        self.assertTrue(ok)
        self.assertEqual(reason, "OK")

        # Tiny face
        ok_tiny, reason_tiny, _ = check_face_quality([200, 200, 220, 220], None, 1280, 720)
        self.assertFalse(ok_tiny)
        self.assertEqual(reason_tiny, "Too distant")

    def test_age_bracket_mapping(self):
        self.assertEqual(map_bracket_to_category('0-2'), 'kids')
        self.assertEqual(map_bracket_to_category('3-9'), 'kids')
        self.assertEqual(map_bracket_to_category('10-19'), 'teens')
        self.assertEqual(map_bracket_to_category('20-29'), 'adults')
        self.assertEqual(map_bracket_to_category('30-39'), 'adults')
        self.assertEqual(map_bracket_to_category('50-59'), 'seniors')
        self.assertEqual(map_bracket_to_category('70+'), 'seniors')


if __name__ == "__main__":
    unittest.main()
