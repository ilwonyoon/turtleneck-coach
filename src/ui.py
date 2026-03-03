"""UI overlay drawing utilities for the webcam feed."""

import cv2
import numpy as np

from .calibration import CalibrationData
from .detector import DetectionState, SUSTAINED_DURATION_SEC

# Colors (BGR)
GREEN = (0, 200, 0)
YELLOW = (0, 220, 255)
RED = (0, 0, 255)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
DARK_BG = (30, 30, 30)


def draw_status_overlay(
    frame: np.ndarray,
    state: DetectionState,
    calibrated: bool,
    calibration_progress: float | None = None,
) -> np.ndarray:
    """Draw posture status information on the frame."""
    output = frame.copy()
    h, w = output.shape[:2]

    # Status bar background
    cv2.rectangle(output, (0, 0), (w, 70), DARK_BG, -1)

    if calibration_progress is not None:
        # Calibration mode
        _draw_calibration_ui(output, w, calibration_progress)
    elif not calibrated:
        _draw_text(output, "Press 'C' to calibrate your posture", (20, 45), WHITE)
    else:
        _draw_posture_status(output, state, w)

    # Instructions at bottom
    cv2.rectangle(output, (0, h - 35), (w, h), DARK_BG, -1)
    instructions = "C: Calibrate | Q: Quit | R: Reset calibration"
    _draw_text(output, instructions, (20, h - 12), (150, 150, 150), scale=0.5)

    return output


def _draw_calibration_ui(frame: np.ndarray, width: int, progress: float):
    """Draw calibration progress bar."""
    _draw_text(frame, "CALIBRATING - Sit in correct posture", (20, 30), YELLOW)

    bar_x, bar_y = 20, 50
    bar_w = width - 40
    bar_h = 12
    cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_w, bar_y + bar_h), WHITE, 1)

    fill_w = int(bar_w * progress)
    cv2.rectangle(
        frame, (bar_x, bar_y), (bar_x + fill_w, bar_y + bar_h), GREEN, -1
    )


def _draw_posture_status(frame: np.ndarray, state: DetectionState, width: int):
    """Draw current posture status."""
    if state.is_turtle_neck:
        color = RED
        status = "TURTLE NECK DETECTED - Fix your posture!"
        _draw_warning_border(frame)
    elif state.bad_posture_start is not None:
        color = YELLOW
        import time

        elapsed = time.time() - state.bad_posture_start
        remaining = max(0, SUSTAINED_DURATION_SEC - elapsed)
        status = f"Posture drifting... warning in {remaining:.1f}s"
    else:
        color = GREEN
        status = "Good posture"

    # Status indicator circle
    cv2.circle(frame, (30, 35), 12, color, -1)
    _draw_text(frame, status, (50, 42), color)

    # Headphone fallback indicator
    if state.using_fallback:
        CYAN = (255, 200, 0)
        _draw_text(frame, "[Eye mode - headphones detected]", (50, 60), CYAN, scale=0.4)

    # Deviation score bar
    score = min(state.deviation_score * 3, 1.0)  # normalize to 0-1 range
    bar_x = width - 160
    bar_w = 140
    cv2.rectangle(frame, (bar_x, 20), (bar_x + bar_w, 32), WHITE, 1)
    fill_w = int(bar_w * score)
    bar_color = GREEN if score < 0.3 else YELLOW if score < 0.7 else RED
    cv2.rectangle(frame, (bar_x, 20), (bar_x + fill_w, 32), bar_color, -1)
    _draw_text(frame, "Deviation", (bar_x, 50), (150, 150, 150), scale=0.4)


def _draw_warning_border(frame: np.ndarray):
    """Draw a red border around the frame when turtle neck is detected."""
    h, w = frame.shape[:2]
    thickness = 8
    cv2.rectangle(frame, (0, 0), (w, h), RED, thickness)


def _draw_text(
    frame: np.ndarray,
    text: str,
    pos: tuple[int, int],
    color: tuple[int, int, int],
    scale: float = 0.6,
):
    """Draw text with a dark outline for readability."""
    font = cv2.FONT_HERSHEY_SIMPLEX
    cv2.putText(frame, text, pos, font, scale, BLACK, 3, cv2.LINE_AA)
    cv2.putText(frame, text, pos, font, scale, color, 1, cv2.LINE_AA)
