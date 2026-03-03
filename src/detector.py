"""Turtle neck detection with medical severity grading.

Uses approximate CVA (Craniovertebral Angle) combined with
ear/eye-shoulder distance ratios and Z-depth data for detection.

Medical CVA reference (Physiopedia):
  Normal:   > 53°
  Mild FHP: 40-53°
  Moderate: 30-40°
  Severe:   < 30°

Our approximate CVA is a proxy - not clinically validated,
but uses the same directional logic.
"""

import time
from dataclasses import dataclass
from enum import Enum

from .calibration import CalibrationData
from .camera_position import CameraConfig, CameraPosition
from .pose_detector import PostureMetrics

# Deviation thresholds from baseline
FORWARD_RATIO_THRESHOLD = 0.15
EAR_SHOULDER_THRESHOLD = 0.20
EYE_SHOULDER_THRESHOLD = 0.18
SIDE_VIEW_EAR_THRESHOLD = 0.15
Z_DEPTH_THRESHOLD = 0.03  # Z-coordinate deviation threshold

SUSTAINED_DURATION_SEC = 5.0


class Severity(Enum):
    GOOD = "good"
    MILD = "mild"
    MODERATE = "moderate"
    SEVERE = "severe"


# Approximate CVA thresholds (calibrated to our proxy measurement)
CVA_THRESHOLDS = {
    Severity.GOOD: 50.0,      # above this = good
    Severity.MILD: 38.0,      # above this = mild
    Severity.MODERATE: 25.0,   # above this = moderate
    # below MODERATE = severe
}


@dataclass
class DetectionState:
    """State for tracking posture over time."""

    bad_posture_start: float | None = None
    is_turtle_neck: bool = False
    deviation_score: float = 0.0
    using_fallback: bool = False
    severity: Severity = Severity.GOOD
    current_cva: float = 0.0
    baseline_cva: float = 0.0


def evaluate_posture(
    metrics: PostureMetrics,
    baseline: CalibrationData,
    state: DetectionState,
    camera_config: CameraConfig | None = None,
) -> DetectionState:
    """Evaluate posture against baseline with severity grading."""
    if camera_config is None:
        camera_config = CameraConfig(position=CameraPosition.CENTER)

    if not metrics.landmarks_detected:
        return DetectionState(
            bad_posture_start=state.bad_posture_start,
            is_turtle_neck=False,
            deviation_score=0.0,
            using_fallback=state.using_fallback,
            severity=Severity.GOOD,
            current_cva=0.0,
            baseline_cva=baseline.approx_cva_degrees,
        )

    # Determine severity from approximate CVA
    severity = _classify_severity(metrics.approx_cva_degrees)

    # Head forward ratio deviation
    forward_deviation = _relative_change(
        baseline.head_forward_ratio, metrics.head_forward_ratio
    )

    # Z-depth deviation (ear moving forward of shoulders)
    z_deviation = baseline.ear_forward_z - metrics.ear_forward_z  # positive = worse
    z_score = max(0.0, z_deviation / Z_DEPTH_THRESHOLD) * 0.1 if Z_DEPTH_THRESHOLD > 0 else 0

    use_fallback = not metrics.ears_visible

    if camera_config.is_side_view:
        vert_score, vert_threshold = _evaluate_side_view(
            metrics, baseline, camera_config, use_fallback
        )
        score = vert_score + max(0.0, forward_deviation) * 0.3 + z_score
    else:
        vert_score, vert_threshold = _evaluate_center_view(
            metrics, baseline, use_fallback
        )
        score = vert_score + max(0.0, forward_deviation) + z_score

    threshold = FORWARD_RATIO_THRESHOLD + vert_threshold

    now = time.time()
    is_currently_bad = score > threshold * 0.5

    if is_currently_bad:
        start = state.bad_posture_start if state.bad_posture_start else now
        duration = now - start
        is_turtle = duration >= SUSTAINED_DURATION_SEC
        return DetectionState(
            bad_posture_start=start,
            is_turtle_neck=is_turtle,
            deviation_score=score,
            using_fallback=use_fallback,
            severity=severity,
            current_cva=metrics.approx_cva_degrees,
            baseline_cva=baseline.approx_cva_degrees,
        )

    return DetectionState(
        bad_posture_start=None,
        is_turtle_neck=False,
        deviation_score=score,
        using_fallback=use_fallback,
        severity=severity,
        current_cva=metrics.approx_cva_degrees,
        baseline_cva=baseline.approx_cva_degrees,
    )


def _classify_severity(approx_cva: float) -> Severity:
    """Classify posture severity based on approximate CVA."""
    if approx_cva >= CVA_THRESHOLDS[Severity.GOOD]:
        return Severity.GOOD
    elif approx_cva >= CVA_THRESHOLDS[Severity.MILD]:
        return Severity.MILD
    elif approx_cva >= CVA_THRESHOLDS[Severity.MODERATE]:
        return Severity.MODERATE
    return Severity.SEVERE


def _evaluate_center_view(
    metrics: PostureMetrics,
    baseline: CalibrationData,
    use_fallback: bool,
) -> tuple[float, float]:
    if not use_fallback:
        avg_bl = (baseline.ear_shoulder_distance_left + baseline.ear_shoulder_distance_right) / 2
        avg_cur = (metrics.ear_shoulder_distance_left + metrics.ear_shoulder_distance_right) / 2
        deviation = _relative_change(avg_bl, avg_cur)
        return max(0.0, -deviation), EAR_SHOULDER_THRESHOLD
    else:
        avg_bl = (baseline.eye_shoulder_distance_left + baseline.eye_shoulder_distance_right) / 2
        avg_cur = (metrics.eye_shoulder_distance_left + metrics.eye_shoulder_distance_right) / 2
        deviation = _relative_change(avg_bl, avg_cur)
        return max(0.0, -deviation), EYE_SHOULDER_THRESHOLD


def _evaluate_side_view(
    metrics: PostureMetrics,
    baseline: CalibrationData,
    camera_config: CameraConfig,
    use_fallback: bool,
) -> tuple[float, float]:
    primary = camera_config.primary_side

    if not use_fallback:
        if primary == "left":
            bl, cur = baseline.ear_shoulder_distance_left, metrics.ear_shoulder_distance_left
        elif primary == "right":
            bl, cur = baseline.ear_shoulder_distance_right, metrics.ear_shoulder_distance_right
        else:
            bl = (baseline.ear_shoulder_distance_left + baseline.ear_shoulder_distance_right) / 2
            cur = (metrics.ear_shoulder_distance_left + metrics.ear_shoulder_distance_right) / 2
        deviation = _relative_change(bl, cur)
        return max(0.0, -deviation), SIDE_VIEW_EAR_THRESHOLD
    else:
        if primary == "left":
            bl, cur = baseline.eye_shoulder_distance_left, metrics.eye_shoulder_distance_left
        elif primary == "right":
            bl, cur = baseline.eye_shoulder_distance_right, metrics.eye_shoulder_distance_right
        else:
            bl = (baseline.eye_shoulder_distance_left + baseline.eye_shoulder_distance_right) / 2
            cur = (metrics.eye_shoulder_distance_left + metrics.eye_shoulder_distance_right) / 2
        deviation = _relative_change(bl, cur)
        return max(0.0, -deviation), EYE_SHOULDER_THRESHOLD


def _relative_change(baseline_val: float, current_val: float) -> float:
    if baseline_val == 0:
        return 0.0
    return (current_val - baseline_val) / baseline_val
