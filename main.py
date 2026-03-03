"""Turtle Neck Detector - Main Application.

Detects forward head posture (turtle neck) using your webcam
and alerts you to correct your posture.

Usage:
    source venv/bin/activate
    python main.py

Controls:
    C - Calibrate (sit in correct posture first)
    R - Reset calibration
    Q - Quit
"""

import sys

import cv2
import numpy as np

from src.calibration import (
    CALIBRATION_SAMPLES,
    collect_calibration,
    load_calibration,
    save_calibration,
)
from src.camera_position import CameraConfig, CameraPosition
from src.detector import DetectionState, evaluate_posture
from src.notifier import Notifier
from src.pose_detector import PoseDetector, PostureMetrics
from src.ui import draw_status_overlay

# Colors (BGR)
WHITE = (255, 255, 255)
GREEN = (0, 200, 0)
DARK_BG = (30, 30, 30)
HIGHLIGHT = (255, 200, 0)


def select_camera_position(cap: cv2.VideoCapture) -> CameraConfig:
    """
    Show a visual camera position selector overlay on the webcam feed.
    User presses 1/2/3 to choose.
    """
    options = [
        ("1: Center (front)", CameraPosition.CENTER),
        ("2: Left side", CameraPosition.LEFT),
        ("3: Right side", CameraPosition.RIGHT),
    ]

    selected = None
    while selected is None:
        ret, frame = cap.read()
        if not ret:
            return CameraConfig(position=CameraPosition.CENTER)

        frame = cv2.flip(frame, 1)
        h, w = frame.shape[:2]

        # Dark overlay
        overlay = frame.copy()
        cv2.rectangle(overlay, (0, 0), (w, h), DARK_BG, -1)
        frame = cv2.addWeighted(overlay, 0.7, frame, 0.3, 0)

        # Title
        _draw_text_centered(frame, "Where is your camera?", w // 2, 80, scale=0.9, color=WHITE)
        _draw_text_centered(frame, "Press 1, 2, or 3 to select", w // 2, 120, scale=0.5, color=(150, 150, 150))

        # Draw position diagrams
        _draw_position_diagram(frame, w, h)

        # Option labels
        labels_y = h - 80
        _draw_text_centered(frame, "1: Center", w // 6, labels_y, scale=0.6, color=GREEN)
        _draw_text_centered(frame, "2: Left", w // 2, labels_y, scale=0.6, color=GREEN)
        _draw_text_centered(frame, "3: Right", w * 5 // 6, labels_y, scale=0.6, color=GREEN)

        cv2.imshow("Turtle Neck Detector", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("1"):
            selected = CameraPosition.CENTER
        elif key == ord("2"):
            selected = CameraPosition.LEFT
        elif key == ord("3"):
            selected = CameraPosition.RIGHT
        elif key == ord("q"):
            sys.exit(0)

    config = CameraConfig(position=selected)
    print(f"Camera position: {selected.value}")
    return config


def _draw_position_diagram(frame: np.ndarray, w: int, h: int):
    """Draw simple diagrams showing camera positions."""
    mid_y = h // 2 + 10

    # Center: camera above monitor, facing user
    cx = w // 6
    # Monitor
    cv2.rectangle(frame, (cx - 25, mid_y - 20), (cx + 25, mid_y + 20), WHITE, 2)
    # Camera on top
    cv2.circle(frame, (cx, mid_y - 28), 6, GREEN, -1)
    # User below
    cv2.circle(frame, (cx, mid_y + 55), 15, WHITE, 2)

    # Left: camera to the left
    lx = w // 2
    # Monitor (right side)
    cv2.rectangle(frame, (lx + 10, mid_y - 20), (lx + 60, mid_y + 20), WHITE, 2)
    # Camera (left side)
    cv2.circle(frame, (lx - 35, mid_y - 10), 6, GREEN, -1)
    cv2.rectangle(frame, (lx - 50, mid_y - 5), (lx - 20, mid_y + 15), WHITE, 2)
    # User center
    cv2.circle(frame, (lx + 35, mid_y + 55), 15, WHITE, 2)

    # Right: camera to the right
    rx = w * 5 // 6
    # Monitor (left side)
    cv2.rectangle(frame, (rx - 60, mid_y - 20), (rx - 10, mid_y + 20), WHITE, 2)
    # Camera (right side)
    cv2.circle(frame, (rx + 35, mid_y - 10), 6, GREEN, -1)
    cv2.rectangle(frame, (rx + 20, mid_y - 5), (rx + 50, mid_y + 15), WHITE, 2)
    # User center
    cv2.circle(frame, (rx - 35, mid_y + 55), 15, WHITE, 2)


def _draw_text_centered(
    frame: np.ndarray, text: str, cx: int, cy: int,
    scale: float = 0.6, color=(255, 255, 255),
):
    """Draw text centered at (cx, cy)."""
    font = cv2.FONT_HERSHEY_SIMPLEX
    (tw, th), _ = cv2.getTextSize(text, font, scale, 1)
    x = cx - tw // 2
    y = cy + th // 2
    cv2.putText(frame, text, (x, y), font, scale, (0, 0, 0), 3, cv2.LINE_AA)
    cv2.putText(frame, text, (x, y), font, scale, color, 1, cv2.LINE_AA)


def main():
    print("=" * 50)
    print("  Turtle Neck Detector")
    print("=" * 50)
    print()
    print("Starting webcam...")
    print()

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Cannot open webcam.")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    # Step 1: Select camera position
    camera_config = select_camera_position(cap)

    print()
    print("Controls: C=Calibrate, R=Reset, Q=Quit")
    print()

    detector = PoseDetector()
    notifier = Notifier(cooldown_seconds=60.0)
    state = DetectionState()

    # Try loading existing calibration
    calibration = load_calibration()
    if calibration:
        print("Loaded existing calibration data.")
    else:
        print("No calibration found. Press 'C' to calibrate.")

    calibrating = False
    calibration_samples: list[PostureMetrics] = []

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("ERROR: Failed to read from webcam.")
                break

            frame = cv2.flip(frame, 1)

            metrics, results = detector.process_frame(frame)
            display = detector.draw_landmarks(frame, results)

            if calibrating:
                if metrics.landmarks_detected:
                    calibration_samples.append(metrics)

                progress = len(calibration_samples) / CALIBRATION_SAMPLES

                if len(calibration_samples) >= CALIBRATION_SAMPLES:
                    calibration = collect_calibration(calibration_samples)
                    save_calibration(calibration)
                    calibrating = False
                    calibration_samples = []
                    notifier.reset_cooldown()
                    state = DetectionState()
                    print("Calibration complete! Monitoring posture...")

                display = draw_status_overlay(
                    display, state, calibrated=False, calibration_progress=progress
                )

            elif calibration:
                state = evaluate_posture(metrics, calibration, state, camera_config)

                if state.is_turtle_neck:
                    notifier.notify(
                        "Turtle Neck Alert!",
                        "Your head is too far forward. Sit up straight and pull your chin back.",
                    )

                display = draw_status_overlay(display, state, calibrated=True)

            else:
                display = draw_status_overlay(display, state, calibrated=False)

            cv2.imshow("Turtle Neck Detector", display)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            elif key == ord("c"):
                print("Calibrating... Sit in correct posture.")
                calibrating = True
                calibration_samples = []
            elif key == ord("r"):
                calibration = None
                state = DetectionState()
                print("Calibration reset. Press 'C' to recalibrate.")

    finally:
        detector.release()
        cap.release()
        cv2.destroyAllWindows()
        print("Goodbye!")


if __name__ == "__main__":
    main()
