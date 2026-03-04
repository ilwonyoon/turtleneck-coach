#!/usr/bin/env python3
"""
MediaPipe pose server for TurtleNeckDetector (v2 — tasks API).

Uses mp.tasks.vision.FaceLandmarker (478 face landmarks) and
mp.tasks.vision.PoseLandmarker (33 body landmarks).

Communicates with the Swift app via Unix Domain Socket.
Protocol: length-prefixed binary frames.
  Swift sends: [4-byte big-endian length][JPEG data]
  Python responds: [4-byte big-endian length][JSON data]

Special messages:
  b'SHUTDOWN' -> server exits gracefully
  b'PING'     -> responds with b'PONG'
"""

import json
import math
import os
import signal
import socket
import struct
import sys
import time

import cv2
import mediapipe as mp
import numpy as np

SOCKET_PATH = "/tmp/pt_turtle.sock"

# Resolve model paths relative to this script
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FACE_MODEL_PATH = os.path.join(_SCRIPT_DIR, "models", "face_landmarker.task")
POSE_MODEL_PATH = os.path.join(_SCRIPT_DIR, "models", "pose_landmarker_lite.task")

# --- One Euro Filter (adaptive smoothing) ---

class OneEuroFilter:
    """Reduce jitter while preserving fast movements.
    https://cristal.univ-lille.fr/~casiez/1euro/
    """

    def __init__(self, freq: float = 30.0, min_cutoff: float = 1.0,
                 beta: float = 0.007, d_cutoff: float = 1.0):
        self.freq = freq
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self.x_prev: float | None = None
        self.dx_prev: float = 0.0
        self.t_prev: float | None = None

    def _smoothing_factor(self, cutoff: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        te = 1.0 / self.freq
        return 1.0 / (1.0 + tau / te)

    def __call__(self, x: float, t: float | None = None) -> float:
        if self.x_prev is None:
            self.x_prev = x
            self.t_prev = t or time.monotonic()
            return x

        now = t or time.monotonic()
        dt = now - self.t_prev if self.t_prev else 1.0 / self.freq
        if dt <= 0:
            dt = 1.0 / self.freq
        self.freq = 1.0 / dt
        self.t_prev = now

        a_d = self._smoothing_factor(self.d_cutoff)
        dx = (x - self.x_prev) / dt
        dx_hat = a_d * dx + (1 - a_d) * self.dx_prev

        cutoff = self.min_cutoff + self.beta * abs(dx_hat)
        a = self._smoothing_factor(cutoff)

        x_hat = a * x + (1 - a) * self.x_prev
        self.x_prev = x_hat
        self.dx_prev = dx_hat
        return x_hat


# --- 3D Head Pose from Face Landmarks ---

# Key face mesh landmark indices
FACE_NOSE_TIP = 1
FACE_CHIN = 152
FACE_FOREHEAD = 10
FACE_LEFT_EYE = 33
FACE_RIGHT_EYE = 263

# Pose landmark indices
POSE_LEFT_EAR = 7
POSE_RIGHT_EAR = 8
POSE_LEFT_SHOULDER = 11
POSE_RIGHT_SHOULDER = 12
POSE_NOSE = 0
POSE_LEFT_EYE = 2
POSE_RIGHT_EYE = 5

MAX_RELIABLE_YAW_DEG = 15.0


def sagittal_yaw_factor(head_yaw: float) -> float:
    """Return cos(yaw) factor for sagittal-plane projection."""
    yaw_radians = math.radians(abs(head_yaw))
    yaw_radians = min(yaw_radians, math.pi / 2)
    return max(0.0, math.cos(yaw_radians))


def get_head_pose(face_landmarks, image_width: int, image_height: int):
    """Compute head pitch/yaw/roll directly from 3D face mesh landmarks.

    Uses the face normal vector (cross product of face plane vectors)
    instead of solvePnP, which suffers from 2D projection artifacts.

    face_landmarks: list of NormalizedLandmark with .x, .y, .z attributes
    Returns: dict with pitch, yaw, roll in degrees.
      pitch: positive = head tilting forward (bad posture)
      yaw: positive = turned left, negative = turned right
      roll: head tilt sideways
    """
    def lm_3d(idx):
        lm = face_landmarks[idx]
        return np.array([lm.x, lm.y, lm.z])

    nose = lm_3d(FACE_NOSE_TIP)
    chin = lm_3d(FACE_CHIN)
    forehead = lm_3d(FACE_FOREHEAD)
    left_eye = lm_3d(FACE_LEFT_EYE)
    right_eye = lm_3d(FACE_RIGHT_EYE)

    # Face plane vectors
    up_vec = forehead - chin          # chin → forehead (up direction)
    right_vec = right_eye - left_eye  # left eye → right eye (right direction)

    # Face normal = up × right (points outward from face)
    normal = np.cross(up_vec, right_vec)
    norm_len = np.linalg.norm(normal)
    if norm_len < 1e-8:
        return None
    normal = normal / norm_len

    # Pitch: vertical tilt of face normal
    # MediaPipe y-axis: 0=top, 1=bottom, so positive normal[1] = facing down
    # We want: positive pitch = forward tilt (chin down, bad posture)
    pitch = math.degrees(math.asin(np.clip(normal[1], -1, 1)))

    # Yaw: horizontal rotation of face normal
    # normal[0] > 0 = face pointing right, normal[2] = depth
    yaw = math.degrees(math.atan2(-normal[0], normal[2]))

    # Roll: tilt of eye-to-eye line relative to horizontal
    roll = math.degrees(math.atan2(right_vec[1], right_vec[0]))

    return {
        "pitch": pitch,
        "yaw": yaw,
        "roll": roll,
    }


def compute_geometric_cva(ear_mid, shoulder_mid, head_yaw: float = 0.0):
    """Compute CVA from ear-to-shoulder geometry (2D projected angle)."""
    horizontal_dist = abs(ear_mid[0] - shoulder_mid[0])
    dy = shoulder_mid[1] - ear_mid[1]  # positive = ear above shoulder (good)
    if dy <= 1:
        return 10.0

    # Project horizontal displacement onto sagittal plane to compensate yaw perspective.
    sagittal_forward = horizontal_dist * sagittal_yaw_factor(head_yaw)
    angle = math.degrees(math.atan2(dy, max(1e-6, sagittal_forward)))
    return max(10.0, min(90.0, angle))


def is_front_facing(ear_left, ear_right, shoulder_left, shoulder_right):
    """Detect if camera is front-facing (ears nearly equidistant from center).

    In front view, both ears visible and roughly symmetric.
    In side view, one ear is much closer to center than the other.
    """
    ear_span = abs(ear_right[0] - ear_left[0])
    shoulder_span = abs(shoulder_right[0] - shoulder_left[0])
    if shoulder_span < 0.01:
        return True
    # Front-facing: ear span is small relative to shoulder span
    # Side view: ear span approaches shoulder span
    ratio = ear_span / shoulder_span
    return ratio < 0.6  # front-facing if ears span < 60% of shoulders



def compute_combined_cva(geometric_cva: float, head_pitch: float,
                         front_facing: bool = True) -> float:
    """Combine geometric CVA and head pitch into a single CVA estimate.

    head_pitch: normalized forward tilt (0 = straight, 20 = moderate forward).
    Maps to CVA-like scale: tilt 0 -> CVA ~60, tilt 15 -> CVA ~38, tilt 30 -> CVA ~15.

    For front-facing cameras, geometric CVA is unreliable (always ~80-90)
    so we rely on head_pitch exclusively.

    """
    # 3D-based pitch: magnitude indicates forward/backward tilt
    # Sign depends on camera angle, so use absolute value
    # Dead zone: < 5° is normal upright posture variation
    effective_tilt = max(0.0, abs(head_pitch) - 5.0)
    pitch_based_cva = max(15.0, min(65.0, 62.0 - effective_tilt * 2.5))

    if front_facing:
        return pitch_based_cva
    else:
        return 0.4 * geometric_cva + 0.6 * pitch_based_cva


class PoseServer:
    """MediaPipe pose analysis server using tasks API."""

    def __init__(self):
        # Create FaceLandmarker
        face_base = mp.tasks.BaseOptions(model_asset_path=FACE_MODEL_PATH)
        face_opts = mp.tasks.vision.FaceLandmarkerOptions(
            base_options=face_base,
            running_mode=mp.tasks.vision.RunningMode.IMAGE,
            num_faces=1,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.face_landmarker = mp.tasks.vision.FaceLandmarker.create_from_options(face_opts)

        # Create PoseLandmarker
        pose_base = mp.tasks.BaseOptions(model_asset_path=POSE_MODEL_PATH)
        pose_opts = mp.tasks.vision.PoseLandmarkerOptions(
            base_options=pose_base,
            running_mode=mp.tasks.vision.RunningMode.IMAGE,
            num_poses=1,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.pose_landmarker = mp.tasks.vision.PoseLandmarker.create_from_options(pose_opts)

        # One Euro Filters for key outputs
        self.filter_pitch = OneEuroFilter(freq=30, min_cutoff=1.0, beta=0.007)
        self.filter_yaw = OneEuroFilter(freq=30, min_cutoff=1.0, beta=0.007)
        self.filter_roll = OneEuroFilter(freq=30, min_cutoff=1.0, beta=0.007)
        self.filter_cva = OneEuroFilter(freq=30, min_cutoff=0.8, beta=0.005)
        self.frame_count = 0

        # Hold-on-loss: keep last valid face data during brief detection drops
        self.last_valid_pitch = 0.0
        self.last_valid_yaw = 0.0
        self.face_lost_frames = 0
        self.max_face_hold_frames = 3  # hold ~1s at 3fps
        self.last_good_cva: float | None = None

    def process_frame(self, jpeg_data: bytes) -> dict:
        """Process a JPEG frame and return pose analysis results."""
        arr = np.frombuffer(jpeg_data, dtype=np.uint8)
        image_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if image_bgr is None:
            return {"error": "failed to decode image"}

        h, w = image_bgr.shape[:2]
        image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)

        # Run both detectors
        face_result = self.face_landmarker.detect(mp_image)
        pose_result = self.pose_landmarker.detect(mp_image)

        now = time.monotonic()
        self.frame_count += 1

        response: dict = {
            "head_pitch": 0.0,
            "head_yaw": 0.0,
            "head_roll": 0.0,
            "ear_left": [0.0, 0.0],
            "ear_right": [0.0, 0.0],
            "shoulder_left": [0.0, 0.0],
            "shoulder_right": [0.0, 0.0],
            "nose": [0.0, 0.0],
            "neck_mid": [0.0, 0.0],
            "left_eye": [0.0, 0.0],
            "right_eye": [0.0, 0.0],
            "cva_angle": 0.0,
            "confidence": 0.0,
            "frame_number": self.frame_count,
            "face_landmarks": [],  # all 478 face landmarks as flat [x0,y0,z0,x1,y1,z1,...]
            "yaw_low_confidence": False,
        }

        has_face = len(face_result.face_landmarks) > 0
        has_pose = len(pose_result.pose_landmarks) > 0

        if not has_face and not has_pose:
            return response

        # --- Head pose from face mesh ---
        head_pitch = 0.0
        head_yaw = 0.0
        head_roll = 0.0

        if has_face:
            face_lms = face_result.face_landmarks[0]  # list of NormalizedLandmark
            head_angles = get_head_pose(face_lms, w, h)
            if head_angles:
                # 3D-based: already 0 = straight, positive = forward tilt
                head_pitch = self.filter_pitch(head_angles["pitch"], now)
                head_yaw = self.filter_yaw(head_angles["yaw"], now)
                head_roll = self.filter_roll(head_angles["roll"], now)

            # Update hold-on-loss state with valid face data
            self.last_valid_pitch = head_pitch
            self.last_valid_yaw = head_yaw
            self.face_lost_frames = 0

            # Send ALL 478 face landmarks as flat array [x0,y0,z0,x1,y1,z1,...] (3D)
            # Tessellation edges are constant and stored on Swift side
            face_landmarks_flat = []
            for lm in face_lms:
                face_landmarks_flat.append(round(lm.x, 4))
                face_landmarks_flat.append(round(lm.y, 4))
                face_landmarks_flat.append(round(lm.z, 4))
            response["face_landmarks"] = face_landmarks_flat
        else:
            # Hold-on-loss: use last valid pitch/yaw during brief face detection drops
            if self.face_lost_frames < self.max_face_hold_frames:
                head_pitch = self.last_valid_pitch
                head_yaw = self.last_valid_yaw
                self.face_lost_frames += 1

        response["head_pitch"] = round(head_pitch, 2)
        response["head_yaw"] = round(head_yaw, 2)
        response["head_roll"] = round(head_roll, 2)

        # --- Pose landmarks ---
        if has_pose:
            pose_lms = pose_result.pose_landmarks[0]  # list of NormalizedLandmark

            def lm_xy(idx):
                lm = pose_lms[idx]
                return [round(lm.x, 4), round(lm.y, 4)]

            def lm_vis(idx):
                return pose_lms[idx].visibility if hasattr(pose_lms[idx], 'visibility') else 0.5

            l_ear = lm_xy(POSE_LEFT_EAR)
            r_ear = lm_xy(POSE_RIGHT_EAR)
            l_sh = lm_xy(POSE_LEFT_SHOULDER)
            r_sh = lm_xy(POSE_RIGHT_SHOULDER)
            nose = lm_xy(POSE_NOSE)
            l_eye = lm_xy(POSE_LEFT_EYE)
            r_eye = lm_xy(POSE_RIGHT_EYE)

            ear_mid = [(l_ear[0] + r_ear[0]) / 2, (l_ear[1] + r_ear[1]) / 2]
            sh_mid = [(l_sh[0] + r_sh[0]) / 2, (l_sh[1] + r_sh[1]) / 2]
            neck_mid = [round(sh_mid[0], 4), round(sh_mid[1], 4)]

            response["ear_left"] = l_ear
            response["ear_right"] = r_ear
            response["shoulder_left"] = l_sh
            response["shoulder_right"] = r_sh
            response["nose"] = nose
            response["neck_mid"] = neck_mid
            response["left_eye"] = l_eye
            response["right_eye"] = r_eye

            # Confidence: average visibility of key landmarks
            vis_keys = [POSE_LEFT_EAR, POSE_RIGHT_EAR,
                        POSE_LEFT_SHOULDER, POSE_RIGHT_SHOULDER, POSE_NOSE]
            avg_vis = sum(lm_vis(i) for i in vis_keys) / len(vis_keys)
            response["confidence"] = round(avg_vis, 3)

            # --- CVA calculation ---
            ear_mid_px = [ear_mid[0] * w, ear_mid[1] * h]
            sh_mid_px = [sh_mid[0] * w, sh_mid[1] * h]
            geometric_cva = compute_geometric_cva(ear_mid_px, sh_mid_px, head_yaw=head_yaw)

            front = is_front_facing(l_ear, r_ear, l_sh, r_sh)

            if has_face and head_pitch != 0.0:
                cva = compute_combined_cva(geometric_cva, head_pitch, front_facing=front)
            else:
                cva = geometric_cva

            yaw_low_confidence = abs(head_yaw) > MAX_RELIABLE_YAW_DEG
            response["yaw_low_confidence"] = yaw_low_confidence
            if yaw_low_confidence:
                response["confidence"] = round(min(response["confidence"], 0.2), 3)
                if self.last_good_cva is not None:
                    cva = self.last_good_cva

            cva = self.filter_cva(cva, now)
            response["cva_angle"] = round(cva, 2)
            if not yaw_low_confidence:
                self.last_good_cva = cva
        elif has_face:
            # Face only, no pose — use pitch-based CVA estimate
            pitch_cva = max(15.0, min(70.0, 65.0 - head_pitch * 1.33))
            yaw_low_confidence = abs(head_yaw) > MAX_RELIABLE_YAW_DEG
            response["yaw_low_confidence"] = yaw_low_confidence
            if yaw_low_confidence and self.last_good_cva is not None:
                pitch_cva = self.last_good_cva
            pitch_cva = self.filter_cva(pitch_cva, now)
            response["cva_angle"] = round(pitch_cva, 2)
            if yaw_low_confidence:
                response["confidence"] = 0.2
            else:
                response["confidence"] = 0.5
                self.last_good_cva = pitch_cva

        return response

    def cleanup(self):
        self.face_landmarker.close()
        self.pose_landmarker.close()


def recv_exact(conn: socket.socket, n: int) -> bytes:
    """Receive exactly n bytes from socket."""
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk:
            raise ConnectionError("client disconnected")
        data += chunk
    return data


def send_response(conn: socket.socket, payload: bytes):
    """Send length-prefixed response."""
    length = struct.pack(">I", len(payload))
    conn.sendall(length + payload)


def run_server():
    """Main server loop."""
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    server = PoseServer()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(SOCKET_PATH)
    sock.listen(1)
    sock.settimeout(None)

    print(f"[pose_server] Listening on {SOCKET_PATH}", flush=True)

    def handle_shutdown(signum, frame):
        print("[pose_server] Shutting down...", flush=True)
        server.cleanup()
        sock.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)

    while True:
        try:
            conn, _ = sock.accept()
            print("[pose_server] Client connected", flush=True)

            while True:
                try:
                    length_data = recv_exact(conn, 4)
                    length = struct.unpack(">I", length_data)[0]

                    if length > 10_000_000:
                        print(f"[pose_server] Frame too large: {length}", flush=True)
                        break

                    frame_data = recv_exact(conn, length)

                    if frame_data == b"SHUTDOWN":
                        print("[pose_server] Shutdown requested", flush=True)
                        conn.close()
                        handle_shutdown(None, None)
                        return

                    if frame_data == b"PING":
                        send_response(conn, b"PONG")
                        continue

                    result = server.process_frame(frame_data)
                    json_bytes = json.dumps(result).encode("utf-8")
                    send_response(conn, json_bytes)

                except ConnectionError:
                    print("[pose_server] Client disconnected", flush=True)
                    break
                except Exception as e:
                    print(f"[pose_server] Error processing frame: {e}", flush=True)
                    try:
                        error_resp = json.dumps({"error": str(e)}).encode("utf-8")
                        send_response(conn, error_resp)
                    except Exception:
                        break

            conn.close()

        except Exception as e:
            print(f"[pose_server] Accept error: {e}", flush=True)
            time.sleep(1)


def run_test():
    """Test mode: process webcam frames and print results."""
    server = PoseServer()
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Cannot open webcam")
        sys.exit(1)

    print("Testing MediaPipe pose server (press 'q' to quit)...")
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        _, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
        result = server.process_frame(jpeg.tobytes())

        pitch = result["head_pitch"]
        cva = result["cva_angle"]
        conf = result["confidence"]
        print(f"\rPitch: {pitch:6.1f}°  CVA: {cva:5.1f}°  Conf: {conf:.2f}  ", end="", flush=True)

        cv2.imshow("Test", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()
    server.cleanup()


if __name__ == "__main__":
    if "--test" in sys.argv:
        run_test()
    else:
        run_server()
