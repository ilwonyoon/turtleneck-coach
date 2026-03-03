"""Pose detection module using MediaPipe PoseLandmarker (tasks API).

Extracts posture landmarks including Z-depth for approximate CVA calculation.
Supports fallback to eye landmarks when ears are occluded by headphones.
"""

import math
from dataclasses import dataclass
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

EAR_VISIBILITY_THRESHOLD = 0.5
MODEL_PATH = Path(__file__).parent.parent / "pose_landmarker_lite.task"


@dataclass(frozen=True)
class PostureMetrics:
    """Immutable posture measurement data."""

    # 2D pixel distances
    ear_shoulder_distance_left: float
    ear_shoulder_distance_right: float
    eye_shoulder_distance_left: float
    eye_shoulder_distance_right: float
    head_forward_ratio: float  # nose-to-shoulder-midpoint vs shoulder-width
    head_tilt_angle: float

    # Depth-based (Z coordinate from MediaPipe, normalized)
    ear_forward_z: float  # avg ear Z relative to shoulder Z (negative = forward)
    nose_forward_z: float  # nose Z relative to shoulder midpoint Z

    # Approximate CVA (using depth + vertical data)
    approx_cva_degrees: float  # estimated craniovertebral angle

    shoulder_evenness: float
    ears_visible: bool
    landmarks_detected: bool


_EMPTY_METRICS = PostureMetrics(
    ear_shoulder_distance_left=0,
    ear_shoulder_distance_right=0,
    eye_shoulder_distance_left=0,
    eye_shoulder_distance_right=0,
    head_forward_ratio=0,
    head_tilt_angle=0,
    ear_forward_z=0,
    nose_forward_z=0,
    approx_cva_degrees=0,
    shoulder_evenness=0,
    ears_visible=False,
    landmarks_detected=False,
)


class PoseDetector:
    """Extracts posture-related landmarks from webcam frames."""

    def __init__(self, min_detection_confidence=0.7, min_tracking_confidence=0.5):
        vision = mp.tasks.vision

        options = vision.PoseLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(
                model_asset_path=str(MODEL_PATH),
            ),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=1,
            min_pose_detection_confidence=min_detection_confidence,
            min_pose_presence_confidence=min_detection_confidence,
            min_tracking_confidence=min_tracking_confidence,
        )
        self._landmarker = vision.PoseLandmarker.create_from_options(options)
        self._pl = vision.PoseLandmark
        self._connections = vision.PoseLandmarksConnections.POSE_LANDMARKS
        self._frame_timestamp_ms = 0

    def process_frame(self, frame: np.ndarray) -> tuple[PostureMetrics, list | None]:
        """Process a BGR frame and return posture metrics + raw landmarks list."""
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        self._frame_timestamp_ms += 33
        result = self._landmarker.detect_for_video(image, self._frame_timestamp_ms)

        if not result.pose_landmarks or len(result.pose_landmarks) == 0:
            return _EMPTY_METRICS, None

        landmarks = result.pose_landmarks[0]
        pl = self._pl
        h, w = frame.shape[:2]

        left_ear = landmarks[pl.LEFT_EAR]
        right_ear = landmarks[pl.RIGHT_EAR]
        left_eye_outer = landmarks[pl.LEFT_EYE_OUTER]
        right_eye_outer = landmarks[pl.RIGHT_EYE_OUTER]
        left_shoulder = landmarks[pl.LEFT_SHOULDER]
        right_shoulder = landmarks[pl.RIGHT_SHOULDER]
        nose = landmarks[pl.NOSE]

        ears_visible = (
            left_ear.visibility > EAR_VISIBILITY_THRESHOLD
            and right_ear.visibility > EAR_VISIBILITY_THRESHOLD
        )

        # Pixel coordinates
        left_ear_px = (left_ear.x * w, left_ear.y * h)
        right_ear_px = (right_ear.x * w, right_ear.y * h)
        left_eye_outer_px = (left_eye_outer.x * w, left_eye_outer.y * h)
        right_eye_outer_px = (right_eye_outer.x * w, right_eye_outer.y * h)
        left_shoulder_px = (left_shoulder.x * w, left_shoulder.y * h)
        right_shoulder_px = (right_shoulder.x * w, right_shoulder.y * h)
        nose_px = (nose.x * w, nose.y * h)

        # 2D distances
        ear_shoulder_left = _distance(left_ear_px, left_shoulder_px)
        ear_shoulder_right = _distance(right_ear_px, right_shoulder_px)
        eye_shoulder_left = _distance(left_eye_outer_px, left_shoulder_px)
        eye_shoulder_right = _distance(right_eye_outer_px, right_shoulder_px)

        shoulder_mid = (
            (left_shoulder_px[0] + right_shoulder_px[0]) / 2,
            (left_shoulder_px[1] + right_shoulder_px[1]) / 2,
        )
        shoulder_width = _distance(left_shoulder_px, right_shoulder_px)
        nose_to_mid = _distance(nose_px, shoulder_mid)
        head_forward_ratio = nose_to_mid / shoulder_width if shoulder_width > 0 else 0

        # Head tilt
        if ears_visible:
            dx = right_ear_px[0] - left_ear_px[0]
            dy = right_ear_px[1] - left_ear_px[1]
        else:
            dx = right_eye_outer_px[0] - left_eye_outer_px[0]
            dy = right_eye_outer_px[1] - left_eye_outer_px[1]
        head_tilt = math.degrees(math.atan2(dy, dx)) if dx != 0 else 0

        # Z-depth analysis (MediaPipe z is negative toward camera)
        shoulder_mid_z = (left_shoulder.z + right_shoulder.z) / 2
        ear_mid_z = (left_ear.z + right_ear.z) / 2
        ear_forward_z = ear_mid_z - shoulder_mid_z  # negative = ears forward of shoulders
        nose_forward_z = nose.z - shoulder_mid_z

        # Approximate CVA calculation
        # CVA = angle between horizontal and line from C7 (approx shoulder) to ear
        # In frontal camera: use Z as forward displacement, Y as vertical displacement
        ear_mid_y = (left_ear.y + right_ear.y) / 2
        shoulder_mid_y = (left_shoulder.y + right_shoulder.y) / 2

        # Vertical distance (ear above shoulder) in normalized coords
        vertical = shoulder_mid_y - ear_mid_y  # positive = ear above shoulder
        # Forward distance (depth displacement)
        forward = abs(ear_forward_z)  # how far ear is from shoulder in Z

        if vertical > 0.01:
            # CVA ≈ atan2(vertical, forward) - larger angle = better posture
            approx_cva = math.degrees(math.atan2(vertical, forward))
            approx_cva = min(90.0, max(0.0, approx_cva))
        else:
            approx_cva = 0.0

        shoulder_evenness = abs(left_shoulder_px[1] - right_shoulder_px[1])

        metrics = PostureMetrics(
            ear_shoulder_distance_left=ear_shoulder_left,
            ear_shoulder_distance_right=ear_shoulder_right,
            eye_shoulder_distance_left=eye_shoulder_left,
            eye_shoulder_distance_right=eye_shoulder_right,
            head_forward_ratio=head_forward_ratio,
            head_tilt_angle=head_tilt,
            ear_forward_z=ear_forward_z,
            nose_forward_z=nose_forward_z,
            approx_cva_degrees=approx_cva,
            shoulder_evenness=shoulder_evenness,
            ears_visible=ears_visible,
            landmarks_detected=True,
        )

        return metrics, landmarks

    def draw_landmarks(self, frame: np.ndarray, landmarks: list | None) -> np.ndarray:
        """Draw pose landmarks on a copy of the frame."""
        annotated = frame.copy()
        if landmarks is None:
            return annotated

        h, w = annotated.shape[:2]

        for connection in self._connections:
            start = landmarks[connection.start]
            end = landmarks[connection.end]
            start_pt = (int(start.x * w), int(start.y * h))
            end_pt = (int(end.x * w), int(end.y * h))
            cv2.line(annotated, start_pt, end_pt, (0, 200, 0), 2)

        for lm in landmarks:
            pt = (int(lm.x * w), int(lm.y * h))
            cv2.circle(annotated, pt, 3, (0, 255, 0), -1)

        return annotated

    def release(self):
        """Release MediaPipe resources."""
        self._landmarker.close()


def _distance(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    return math.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)
