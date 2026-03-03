"""Side-by-side CVA comparison: Python (MediaPipe) vs Swift (Apple Vision 3D).

Runs the Python pose detector and logs CVA to /tmp/turtle_python_cva.log
while the Swift app logs to /tmp/turtle_cvadebug.log.

Usage:
  1. Make sure Swift app is already running (menu bar)
  2. Run: python compare_cva.py
  3. Both apps use the same camera simultaneously
  4. Change postures and observe the CVA values side-by-side
"""

import csv
import math
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import cv2

# Add src to path
sys.path.insert(0, str(Path(__file__).parent))
from src.pose_detector import PoseDetector

PYTHON_LOG = "/tmp/turtle_python_cva.log"
SWIFT_LOG = "/tmp/turtle_cvadebug.log"
COMPARISON_CSV = "/tmp/turtle_cva_comparison.csv"


def get_latest_swift_cva() -> tuple[float | None, str]:
    """Read the latest 3D CVA value from Swift debug log."""
    try:
        with open(SWIFT_LOG) as f:
            lines = f.readlines()
        # Find last [3D] line
        for line in reversed(lines):
            if "[3D]" in line:
                # Parse: [3D] vert=0.112 rawFwd=0.046 ampFwd=0.093 → CVA=50.4°
                m = re.search(r"CVA=([\d.]+)", line)
                raw_m = re.search(r"rawFwd=([\d.]+)", line)
                vert_m = re.search(r"vert=([\d.]+)", line)
                if m:
                    cva = float(m.group(1))
                    raw_fwd = float(raw_m.group(1)) if raw_m else 0
                    vert = float(vert_m.group(1)) if vert_m else 0
                    return cva, f"vert={vert:.3f} rawFwd={raw_fwd:.3f}"
        return None, ""
    except FileNotFoundError:
        return None, ""


def main():
    print("=" * 70)
    print("  CVA Comparison: Python (MediaPipe) vs Swift (Apple Vision 3D)")
    print("=" * 70)
    print()
    print("Make sure the Swift TurtleNeckDetector app is running in the menu bar.")
    print("Press Ctrl+C to stop.")
    print()

    detector = PoseDetector()
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Cannot open camera")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    # CSV for later analysis
    with open(COMPARISON_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "timestamp", "python_cva", "python_vertical", "python_forward_z",
            "swift_cva", "swift_detail"
        ])

    # Clear python log
    with open(PYTHON_LOG, "w") as f:
        f.write(f"Python CVA comparison started at {datetime.now()}\n")

    print(f"{'Time':>10} | {'Python CVA':>12} | {'Swift CVA':>12} | {'Diff':>8} | {'Python Z-fwd':>12} | Notes")
    print("-" * 80)

    frame_count = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.1)
                continue

            frame = cv2.flip(frame, 1)
            metrics, landmarks = detector.process_frame(frame)

            frame_count += 1
            # Only log every 10th frame (~3Hz at 30fps)
            if frame_count % 10 != 0:
                # Still show video
                if landmarks:
                    display = detector.draw_landmarks(frame, landmarks)
                else:
                    display = frame
                cv2.imshow("Python Pose (CVA comparison)", display)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
                continue

            py_cva = metrics.approx_cva_degrees if metrics.landmarks_detected else None
            py_vert = 0.0
            py_fwd = 0.0

            if metrics.landmarks_detected:
                py_fwd = abs(metrics.ear_forward_z)
                # Reconstruct vertical from CVA and forward
                if py_cva and py_cva > 0 and py_fwd > 0:
                    py_vert = py_fwd * math.tan(math.radians(py_cva))

            swift_cva, swift_detail = get_latest_swift_cva()

            now_str = datetime.now().strftime("%H:%M:%S")

            diff_str = ""
            if py_cva is not None and swift_cva is not None:
                diff = swift_cva - py_cva
                diff_str = f"{diff:+.1f}°"

            py_str = f"{py_cva:.1f}°" if py_cva else "N/A"
            sw_str = f"{swift_cva:.1f}°" if swift_cva else "N/A"

            note = ""
            if py_cva and py_cva < 38:
                note = "** BAD (Python)"
            elif py_cva and py_cva < 50:
                note = "* MILD (Python)"

            print(f"{now_str:>10} | {py_str:>12} | {sw_str:>12} | {diff_str:>8} | {py_fwd:>12.4f} | {note}")

            # Log to file
            log_line = f"{now_str} PyCVA={py_str} SwiftCVA={sw_str} diff={diff_str} py_fwd_z={py_fwd:.4f}\n"
            with open(PYTHON_LOG, "a") as f:
                f.write(log_line)

            # CSV
            with open(COMPARISON_CSV, "a", newline="") as f:
                writer = csv.writer(f)
                writer.writerow([
                    now_str,
                    f"{py_cva:.1f}" if py_cva else "",
                    f"{py_vert:.4f}",
                    f"{py_fwd:.4f}",
                    f"{swift_cva:.1f}" if swift_cva else "",
                    swift_detail,
                ])

            # Show annotated frame
            if landmarks:
                display = detector.draw_landmarks(frame, landmarks)
            else:
                display = frame

            # Add CVA text overlay
            cv2.putText(display, f"Python CVA: {py_str}", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            cv2.putText(display, f"Swift CVA:  {sw_str}", (10, 60),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 200, 255), 2)
            if diff_str:
                cv2.putText(display, f"Diff: {diff_str}", (10, 90),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 0), 2)

            cv2.imshow("Python Pose (CVA comparison)", display)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    except KeyboardInterrupt:
        print("\n\nStopped.")
    finally:
        cap.release()
        cv2.destroyAllWindows()
        detector.release()

    print(f"\nComparison data saved to: {COMPARISON_CSV}")
    print(f"Python log: {PYTHON_LOG}")
    print(f"Swift log:  {SWIFT_LOG}")


if __name__ == "__main__":
    main()
