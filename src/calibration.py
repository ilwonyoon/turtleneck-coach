"""Calibration module with posture validation.

Validates that the user's calibration posture meets minimum medical
standards before accepting it as a baseline.
"""

import json
from dataclasses import asdict, dataclass
from pathlib import Path

from .pose_detector import PostureMetrics

CALIBRATION_FILE = Path(__file__).parent.parent / "calibration_data.json"
CALIBRATION_SAMPLES = 30

# Minimum acceptable approximate CVA for calibration (degrees)
# Normal CVA is > 53°. We're lenient since this is an approximation.
MIN_CALIBRATION_CVA = 35.0


@dataclass(frozen=True)
class CalibrationData:
    """Immutable baseline posture measurements."""

    ear_shoulder_distance_left: float
    ear_shoulder_distance_right: float
    eye_shoulder_distance_left: float
    eye_shoulder_distance_right: float
    head_forward_ratio: float
    head_tilt_angle: float
    ear_forward_z: float
    nose_forward_z: float
    approx_cva_degrees: float
    shoulder_evenness: float
    ears_were_visible: bool


@dataclass(frozen=True)
class CalibrationResult:
    """Result of calibration attempt with validation."""

    data: CalibrationData | None
    is_valid: bool
    message: str
    approx_cva: float  # the measured CVA for display


def collect_calibration(samples: list[PostureMetrics]) -> CalibrationResult:
    """
    Average samples into baseline and validate posture quality.

    Returns CalibrationResult with validation status and feedback.
    """
    valid = [s for s in samples if s.landmarks_detected]
    if not valid:
        return CalibrationResult(
            data=None,
            is_valid=False,
            message="No pose detected. Make sure your face and shoulders are visible.",
            approx_cva=0,
        )

    n = len(valid)
    ears_visible_count = sum(1 for s in valid if s.ears_visible)
    ears_mostly_visible = ears_visible_count > n * 0.5

    avg_cva = sum(s.approx_cva_degrees for s in valid) / n

    data = CalibrationData(
        ear_shoulder_distance_left=sum(s.ear_shoulder_distance_left for s in valid) / n,
        ear_shoulder_distance_right=sum(s.ear_shoulder_distance_right for s in valid) / n,
        eye_shoulder_distance_left=sum(s.eye_shoulder_distance_left for s in valid) / n,
        eye_shoulder_distance_right=sum(s.eye_shoulder_distance_right for s in valid) / n,
        head_forward_ratio=sum(s.head_forward_ratio for s in valid) / n,
        head_tilt_angle=sum(s.head_tilt_angle for s in valid) / n,
        ear_forward_z=sum(s.ear_forward_z for s in valid) / n,
        nose_forward_z=sum(s.nose_forward_z for s in valid) / n,
        approx_cva_degrees=avg_cva,
        shoulder_evenness=sum(s.shoulder_evenness for s in valid) / n,
        ears_were_visible=ears_mostly_visible,
    )

    # Validate posture quality
    if avg_cva < MIN_CALIBRATION_CVA:
        return CalibrationResult(
            data=data,
            is_valid=False,
            message=(
                f"Your posture seems too far forward (CVA ~{avg_cva:.0f}°). "
                "Sit up straight: ears over shoulders, chin slightly tucked. "
                "Try again with better posture."
            ),
            approx_cva=avg_cva,
        )

    return CalibrationResult(
        data=data,
        is_valid=True,
        message=f"Calibration successful! (CVA ~{avg_cva:.0f}°)",
        approx_cva=avg_cva,
    )


def save_calibration(data: CalibrationData, path: Path = CALIBRATION_FILE) -> None:
    """Save calibration data to JSON file."""
    path.write_text(json.dumps(asdict(data), indent=2))


def load_calibration(path: Path = CALIBRATION_FILE) -> CalibrationData | None:
    """Load calibration data from JSON file, or None if not found."""
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text())
        return CalibrationData(**raw)
    except (json.JSONDecodeError, TypeError, KeyError):
        return None
