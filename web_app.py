"""Turtle Neck Detector - Web Application.

Runs on localhost:8080 with live webcam feed, posture detection
with severity grading and dynamic feedback.
"""

import threading
import time

import cv2
from flask import Flask, Response, jsonify, render_template_string, request

from src.calibration import (
    CALIBRATION_SAMPLES,
    collect_calibration,
    load_calibration,
    save_calibration,
)
from src.camera_position import CameraConfig, CameraPosition
from src.detector import SUSTAINED_DURATION_SEC, DetectionState, Severity, evaluate_posture
from src.notifier import Notifier
from src.pose_detector import PoseDetector, PostureMetrics

app = Flask(__name__)

# Shared state
lock = threading.Lock()
camera_config = CameraConfig(position=CameraPosition.CENTER)
calibration = load_calibration()
state = DetectionState()
calibrating = False
calibration_progress = 0.0
calibration_message = ""
calibration_samples: list[PostureMetrics] = []
notifier = Notifier(cooldown_seconds=60.0)
detector: PoseDetector | None = None
cap = None
good_posture_start: float | None = None  # tracks how long user has been in good posture


def get_detector():
    global detector
    if detector is None:
        detector = PoseDetector()
    return detector


def get_camera():
    global cap
    if cap is None or not cap.isOpened():
        cap = cv2.VideoCapture(0)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    return cap


def generate_frames():
    global state, calibrating, calibration_samples, calibration
    global calibration_progress, calibration_message, good_posture_start

    camera = get_camera()
    pose_detector = get_detector()

    while True:
        ret, frame = camera.read()
        if not ret:
            time.sleep(0.1)
            continue

        frame = cv2.flip(frame, 1)
        metrics, landmarks = pose_detector.process_frame(frame)
        display = pose_detector.draw_landmarks(frame, landmarks)

        with lock:
            if calibrating:
                if metrics.landmarks_detected:
                    calibration_samples.append(metrics)

                calibration_progress = len(calibration_samples) / CALIBRATION_SAMPLES

                if len(calibration_samples) >= CALIBRATION_SAMPLES:
                    result = collect_calibration(calibration_samples)
                    calibration_message = result.message

                    if result.is_valid and result.data is not None:
                        calibration = result.data
                        save_calibration(result.data)
                        notifier.reset_cooldown()
                        state = DetectionState()
                        good_posture_start = time.time()

                    calibrating = False
                    calibration_samples = []
                    calibration_progress = 0.0

            elif calibration:
                state = evaluate_posture(metrics, calibration, state, camera_config)

                # Track good posture duration
                if state.severity == Severity.GOOD and not state.is_turtle_neck:
                    if good_posture_start is None:
                        good_posture_start = time.time()
                else:
                    good_posture_start = None

                if state.is_turtle_neck:
                    severity_msg = {
                        Severity.MILD: "Mild forward head posture detected.",
                        Severity.MODERATE: "Moderate forward head posture. Sit up straight!",
                        Severity.SEVERE: "Severe forward head posture! Take a break and stretch.",
                    }
                    msg = severity_msg.get(
                        state.severity,
                        "Fix your posture - head is too far forward.",
                    )
                    notifier.notify("Turtle Neck Alert!", msg)

        _, buffer = cv2.imencode(".jpg", display, [cv2.IMWRITE_JPEG_QUALITY, 80])
        frame_bytes = buffer.tobytes()

        yield (
            b"--frame\r\n"
            b"Content-Type: image/jpeg\r\n\r\n" + frame_bytes + b"\r\n"
        )

        time.sleep(0.033)


@app.route("/")
def index():
    return render_template_string(HTML_TEMPLATE)


@app.route("/video_feed")
def video_feed():
    return Response(
        generate_frames(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )


@app.route("/calibrate", methods=["POST"])
def calibrate():
    global calibrating, calibration_samples, calibration_progress, calibration_message
    with lock:
        calibrating = True
        calibration_samples = []
        calibration_progress = 0.0
        calibration_message = ""
    return jsonify({"status": "calibrating"})


@app.route("/reset", methods=["POST"])
def reset():
    global calibration, state, calibrating, calibration_progress, calibration_message, good_posture_start
    with lock:
        calibration = None
        state = DetectionState()
        calibrating = False
        calibration_progress = 0.0
        calibration_message = ""
        good_posture_start = None
    return jsonify({"status": "reset"})


@app.route("/set_camera", methods=["POST"])
def set_camera():
    global camera_config
    data = request.get_json()
    position = data.get("position", "center")
    positions = {
        "center": CameraPosition.CENTER,
        "left": CameraPosition.LEFT,
        "right": CameraPosition.RIGHT,
    }
    with lock:
        camera_config = CameraConfig(position=positions.get(position, CameraPosition.CENTER))
    return jsonify({"status": "ok", "position": position})


@app.route("/status")
def get_status():
    with lock:
        remaining = None
        if state.bad_posture_start is not None and not state.is_turtle_neck:
            elapsed = time.time() - state.bad_posture_start
            remaining = max(0, SUSTAINED_DURATION_SEC - elapsed)

        good_duration = 0.0
        if good_posture_start is not None:
            good_duration = time.time() - good_posture_start

        return jsonify({
            "is_turtle_neck": state.is_turtle_neck,
            "deviation_score": round(state.deviation_score, 4),
            "using_fallback": state.using_fallback,
            "calibrated": calibration is not None,
            "calibrating": calibrating,
            "calibration_progress": round(calibration_progress, 2),
            "calibration_message": calibration_message,
            "camera_position": camera_config.position.value,
            "warning_remaining": round(remaining, 1) if remaining is not None else None,
            "severity": state.severity.value,
            "current_cva": round(state.current_cva, 1),
            "baseline_cva": round(state.baseline_cva, 1),
            "good_posture_seconds": round(good_duration, 0),
        })


HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Turtle Neck Detector</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
            background: #0a0a0a; color: #e0e0e0;
            min-height: 100vh; display: flex; flex-direction: column; align-items: center;
        }
        header {
            width: 100%; padding: 16px 20px; text-align: center;
            background: #111; border-bottom: 1px solid #222;
        }
        header h1 { font-size: 1.4rem; font-weight: 600; color: #fff; }
        header p { font-size: 0.8rem; color: #666; margin-top: 2px; }

        .container {
            display: flex; flex-direction: column; align-items: center;
            gap: 14px; padding: 20px; max-width: 720px; width: 100%;
        }

        .camera-selector { display: flex; gap: 8px; align-items: center; }
        .camera-selector label { font-size: 0.85rem; color: #888; margin-right: 4px; }
        .cam-btn {
            padding: 6px 14px; border: 1px solid #333; border-radius: 6px;
            background: #1a1a1a; color: #aaa; font-size: 0.8rem; cursor: pointer; transition: all 0.2s;
        }
        .cam-btn:hover { background: #252525; border-color: #555; }
        .cam-btn.active { background: #0d2a0d; border-color: #30d158; color: #30d158; }

        .video-wrapper {
            position: relative; width: 100%; border-radius: 12px; overflow: hidden;
            border: 2px solid #222; background: #000; transition: border-color 0.3s, box-shadow 0.3s;
        }
        .video-wrapper img { width: 100%; display: block; }
        .video-wrapper.good { border-color: #30d158; }
        .video-wrapper.warning { border-color: #ffd60a; }
        .video-wrapper.mild { border-color: #ffd60a; }
        .video-wrapper.moderate { border-color: #ff9f0a; box-shadow: 0 0 20px rgba(255,159,10,0.3); }
        .video-wrapper.severe { border-color: #ff3b30; box-shadow: 0 0 40px rgba(255,59,48,0.4); }

        .overlay {
            position: absolute; top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.65); display: flex; flex-direction: column;
            align-items: center; justify-content: center; gap: 14px; z-index: 10;
        }
        .overlay.hidden { display: none; }
        .overlay h2 { font-size: 1.2rem; }
        .overlay p { color: #ccc; font-size: 0.85rem; text-align: center; max-width: 80%; line-height: 1.5; }

        .progress-bar-outer {
            width: 80%; max-width: 400px; height: 14px;
            background: #333; border-radius: 7px; overflow: hidden;
        }
        .progress-bar-inner {
            height: 100%; background: linear-gradient(90deg, #30d158, #34c759);
            border-radius: 7px; transition: width 0.2s ease; width: 0%;
        }
        .progress-text { color: #aaa; font-size: 0.85rem; font-variant-numeric: tabular-nums; }

        .posture-guide {
            background: rgba(0,0,0,0.8); border-radius: 8px; padding: 16px;
            text-align: center; max-width: 90%;
        }
        .posture-guide h3 { color: #ffd60a; margin-bottom: 8px; font-size: 0.95rem; }
        .posture-guide ul { text-align: left; color: #bbb; font-size: 0.8rem; list-style: none; padding: 0; }
        .posture-guide li { padding: 3px 0; }
        .posture-guide li::before { content: "\\2713 "; color: #30d158; }

        .cal-result {
            padding: 10px 16px; border-radius: 8px; font-size: 0.85rem;
            text-align: center; max-width: 90%; line-height: 1.4;
        }
        .cal-result.success { background: rgba(48,209,88,0.15); border: 1px solid #30d158; color: #30d158; }
        .cal-result.fail { background: rgba(255,59,48,0.15); border: 1px solid #ff3b30; color: #ff6961; }

        /* Status card */
        .status-card {
            width: 100%; padding: 16px 20px; background: #111;
            border-radius: 10px; border: 1px solid #222; transition: border-color 0.3s;
        }
        .status-card.alert { border-color: #ff3b30; }
        .status-card.great { border-color: #30d158; }

        .status-top { display: flex; align-items: center; gap: 12px; margin-bottom: 8px; }

        .status-dot {
            width: 14px; height: 14px; border-radius: 50%;
            background: #555; flex-shrink: 0; transition: background 0.3s;
        }
        .status-dot.good { background: #30d158; }
        .status-dot.warning { background: #ffd60a; }
        .status-dot.bad { background: #ff3b30; animation: pulse 1s infinite; }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }

        .status-main { font-size: 0.95rem; flex-grow: 1; font-weight: 500; }
        .status-sub { font-size: 0.8rem; color: #888; margin-top: 2px; line-height: 1.4; }

        .badges { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 8px; }
        .badge {
            font-size: 0.7rem; padding: 3px 10px; border-radius: 10px;
            background: #1a1a1a; border: 1px solid #333;
        }
        .badge.eye-mode { border-color: #ffd60a; color: #ffd60a; }
        .badge.cam { border-color: #0a84ff; color: #0a84ff; }
        .badge.streak { border-color: #30d158; color: #30d158; }
        .badge.sev-mild { border-color: #ffd60a; color: #ffd60a; }
        .badge.sev-moderate { border-color: #ff9f0a; color: #ff9f0a; }
        .badge.sev-severe { border-color: #ff3b30; color: #ff3b30; background: rgba(255,59,48,0.1); }

        /* Posture score meter */
        .score-meter { display: flex; align-items: center; gap: 10px; width: 100%; padding: 0 4px; }
        .score-label { font-size: 0.75rem; color: #666; white-space: nowrap; min-width: 80px; }
        .score-track {
            flex-grow: 1; height: 22px; background: #1a1a1a;
            border-radius: 11px; overflow: hidden; position: relative; border: 1px solid #222;
        }
        .score-zones { display: flex; height: 100%; width: 100%; }
        .score-zone { height: 100%; }
        .score-zone.bad { background: rgba(255,59,48,0.25); flex: 25; }
        .score-zone.meh { background: rgba(255,159,10,0.2); flex: 15; }
        .score-zone.ok { background: rgba(255,214,10,0.15); flex: 15; }
        .score-zone.great { background: rgba(48,209,88,0.2); flex: 45; }

        .score-needle {
            position: absolute; top: 2px; bottom: 2px; width: 4px;
            background: #fff; border-radius: 2px; transition: left 0.4s;
            box-shadow: 0 0 8px rgba(255,255,255,0.6);
        }
        .score-emoji { font-size: 1.1rem; min-width: 30px; text-align: center; }
        .score-value {
            font-size: 0.8rem; color: #fff; min-width: 40px; text-align: right;
            font-variant-numeric: tabular-nums;
        }

        .deviation-meter { display: flex; align-items: center; gap: 10px; width: 100%; padding: 0 4px; }
        .deviation-label { font-size: 0.75rem; color: #666; white-space: nowrap; min-width: 80px; }
        .deviation-track { flex-grow: 1; height: 6px; background: #222; border-radius: 3px; overflow: hidden; }
        .deviation-fill {
            height: 100%; border-radius: 3px; transition: width 0.3s, background 0.3s;
            width: 0%; background: #30d158;
        }

        .controls { display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; }
        .btn {
            padding: 10px 22px; border: 1px solid #333; border-radius: 8px;
            background: #1a1a1a; color: #e0e0e0; font-size: 0.85rem;
            cursor: pointer; transition: all 0.15s;
        }
        .btn:hover { background: #2a2a2a; border-color: #555; }
        .btn:active { transform: scale(0.97); }
        .btn.primary { background: #0a84ff; border-color: #0a84ff; color: #fff; }
        .btn.primary:hover { background: #0070e0; }
        .btn.primary:disabled { background: #333; border-color: #333; color: #666; cursor: not-allowed; }
        .btn.danger { border-color: #ff3b30; color: #ff3b30; }
        .btn.danger:hover { background: #1a0808; }
        .shortcut {
            display: inline-block; font-size: 0.65rem; padding: 1px 5px;
            background: #333; border-radius: 3px; margin-left: 6px; color: #999;
        }
    </style>
</head>
<body>
    <header>
        <h1>Turtle Neck Detector</h1>
        <p>Real-time posture monitoring</p>
    </header>

    <div class="container">
        <div class="camera-selector">
            <label>Camera:</label>
            <button class="cam-btn active" id="cam-center" onclick="setCamera('center')">Center</button>
            <button class="cam-btn" id="cam-left" onclick="setCamera('left')">Left</button>
            <button class="cam-btn" id="cam-right" onclick="setCamera('right')">Right</button>
        </div>

        <div class="video-wrapper" id="video-wrapper">
            <img src="/video_feed" alt="Webcam Feed">

            <div class="overlay hidden" id="cal-overlay">
                <h2 style="color:#ffd60a">Calibrating...</h2>
                <div class="posture-guide">
                    <h3>Correct posture checklist</h3>
                    <ul>
                        <li>Feet flat on the floor</li>
                        <li>Back straight against chair</li>
                        <li>Ears directly above shoulders</li>
                        <li>Chin slightly tucked (not jutting forward)</li>
                        <li>Shoulders relaxed, not hunched</li>
                    </ul>
                </div>
                <p>Hold this posture while calibrating</p>
                <div class="progress-bar-outer">
                    <div class="progress-bar-inner" id="cal-progress"></div>
                </div>
                <span class="progress-text" id="cal-percent">0%</span>
            </div>

            <div class="overlay hidden" id="result-overlay">
                <div class="cal-result" id="cal-result"></div>
                <button class="btn primary" onclick="dismissResult()" style="margin-top:8px">OK</button>
            </div>
        </div>

        <!-- Status card -->
        <div class="status-card" id="status-card">
            <div class="status-top">
                <div class="status-dot" id="status-dot"></div>
                <div style="flex-grow:1">
                    <div class="status-main" id="status-main">Press Calibrate to start</div>
                    <div class="status-sub" id="status-sub"></div>
                </div>
            </div>
            <div class="badges" id="badges">
                <span class="badge cam" id="cam-badge">Center</span>
            </div>
        </div>

        <!-- Posture score meter (replaces CVA meter) -->
        <div class="score-meter" id="score-meter" style="display:none">
            <span class="score-label">Posture Score</span>
            <div class="score-track">
                <div class="score-zones">
                    <div class="score-zone bad"></div>
                    <div class="score-zone meh"></div>
                    <div class="score-zone ok"></div>
                    <div class="score-zone great"></div>
                </div>
                <div class="score-needle" id="score-needle" style="left:50%"></div>
            </div>
            <span class="score-emoji" id="score-emoji">-</span>
            <span class="score-value" id="score-value">--</span>
        </div>

        <div class="deviation-meter">
            <span class="deviation-label">Movement</span>
            <div class="deviation-track">
                <div class="deviation-fill" id="deviation-fill"></div>
            </div>
        </div>

        <div class="controls">
            <button class="btn primary" id="cal-btn" onclick="calibrate()">
                Calibrate <span class="shortcut">C</span>
            </button>
            <button class="btn danger" onclick="resetCalibration()">
                Reset <span class="shortcut">R</span>
            </button>
        </div>
    </div>

    <script>
        const $ = id => document.getElementById(id);
        let lastCalMessage = '';
        let showingResult = false;

        // Dynamic good-posture messages
        const goodMessages = [
            { after: 0, main: "Good posture!", sub: "Keep it up" },
            { after: 30, main: "Nice form!", sub: "30 seconds of good posture" },
            { after: 60, main: "Great job!", sub: "1 minute streak going strong" },
            { after: 120, main: "Excellent!", sub: "2 minutes - your neck thanks you" },
            { after: 300, main: "Posture champion!", sub: "5 min streak! Take a stretch break soon" },
            { after: 600, main: "Amazing discipline!", sub: "10 min! Consider standing up briefly" },
            { after: 1200, main: "Incredible focus!", sub: "20 min - time for a quick break?" },
            { after: 1800, main: "You're on fire!", sub: "30 min streak! Stand and stretch" },
        ];

        const warningTips = [
            "Try pulling your chin back slightly",
            "Imagine a string pulling the top of your head up",
            "Roll your shoulders back and down",
            "Check: are your ears above your shoulders?",
        ];
        let tipIndex = 0;

        function getGoodMessage(seconds) {
            let msg = goodMessages[0];
            for (const m of goodMessages) {
                if (seconds >= m.after) msg = m;
            }
            return msg;
        }

        // Convert CVA to a 0-100 posture score for display
        // Maps: CVA 20° -> score ~10, CVA 35° -> ~40, CVA 50° -> ~75, CVA 60°+ -> ~95
        function cvaToScore(cva) {
            if (cva <= 15) return 5;
            if (cva >= 65) return 98;
            // Piecewise linear mapping tuned to real usage range
            return Math.round(5 + (cva - 15) * (93 / 50));
        }

        function scoreToEmoji(score) {
            if (score >= 80) return '\\u{1F929}';   // star-struck
            if (score >= 60) return '\\u{1F60A}';   // smiling
            if (score >= 40) return '\\u{1F610}';   // neutral
            if (score >= 20) return '\\u{1F615}';   // confused
            return '\\u{1F62C}';                     // grimacing
        }

        function formatTime(sec) {
            if (sec < 60) return Math.round(sec) + 's';
            const m = Math.floor(sec / 60);
            const s = Math.round(sec % 60);
            return m + 'm ' + (s > 0 ? s + 's' : '');
        }

        function dismissResult() {
            $('result-overlay').classList.add('hidden');
            showingResult = false;
        }

        async function calibrate() {
            $('cal-btn').disabled = true;
            $('cal-btn').textContent = 'Calibrating...';
            showingResult = false;
            $('result-overlay').classList.add('hidden');
            await fetch('/calibrate', { method: 'POST' });
        }

        async function resetCalibration() {
            showingResult = false;
            $('result-overlay').classList.add('hidden');
            await fetch('/reset', { method: 'POST' });
            $('cal-btn').innerHTML = 'Calibrate <span class="shortcut">C</span>';
            $('cal-btn').disabled = false;
            $('score-meter').style.display = 'none';
        }

        async function setCamera(position) {
            await fetch('/set_camera', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ position }),
            });
            document.querySelectorAll('.cam-btn').forEach(b => b.classList.remove('active'));
            $('cam-' + position).classList.add('active');
            $('cam-badge').textContent = position.charAt(0).toUpperCase() + position.slice(1);
        }

        async function pollStatus() {
            try {
                const res = await fetch('/status');
                const data = await res.json();

                const dot = $('status-dot');
                const main = $('status-main');
                const sub = $('status-sub');
                const wrapper = $('video-wrapper');
                const calOverlay = $('cal-overlay');
                const devFill = $('deviation-fill');
                const card = $('status-card');
                const badges = $('badges');

                wrapper.className = 'video-wrapper';
                card.className = 'status-card';

                // Build badges
                let badgeHtml = '<span class="badge cam">' +
                    data.camera_position.charAt(0).toUpperCase() + data.camera_position.slice(1) + '</span>';
                if (data.using_fallback) badgeHtml += '<span class="badge eye-mode">Eye Mode</span>';

                // Calibrating
                if (data.calibrating) {
                    calOverlay.classList.remove('hidden');
                    const pct = Math.round(data.calibration_progress * 100);
                    $('cal-progress').style.width = pct + '%';
                    $('cal-percent').textContent = pct + '%';
                    dot.className = 'status-dot warning';
                    main.textContent = 'Calibrating... ' + pct + '%';
                    sub.textContent = 'Hold your correct posture';
                    badges.innerHTML = badgeHtml;
                    return;
                }

                calOverlay.classList.add('hidden');

                // Calibration just finished
                if (data.calibration_message && data.calibration_message !== lastCalMessage) {
                    lastCalMessage = data.calibration_message;
                    const resultEl = $('cal-result');
                    resultEl.textContent = data.calibration_message;
                    resultEl.className = data.calibrated ? 'cal-result success' : 'cal-result fail';
                    $('result-overlay').classList.remove('hidden');
                    showingResult = true;
                    $('cal-btn').innerHTML = 'Recalibrate <span class="shortcut">C</span>';
                    $('cal-btn').disabled = false;
                }

                // Posture score meter
                if (data.calibrated) {
                    $('score-meter').style.display = 'flex';
                    const score = cvaToScore(data.current_cva);
                    // Map score 0-100 to needle position
                    $('score-needle').style.left = score + '%';
                    $('score-emoji').textContent = scoreToEmoji(score);
                    $('score-value').textContent = score + '/100';
                }

                // Main status display
                if (!data.calibrated) {
                    dot.className = 'status-dot';
                    main.textContent = 'Press Calibrate to start';
                    sub.textContent = 'Sit in your best posture, then calibrate';
                } else if (data.is_turtle_neck) {
                    dot.className = 'status-dot bad';
                    card.classList.add('alert');

                    const sevLabel = {mild: 'Mild', moderate: 'Moderate', severe: 'Severe'};
                    const sevTip = {
                        mild: 'Pull your chin back and sit up tall',
                        moderate: 'Your head is significantly forward - sit back and realign',
                        severe: 'Stop and take a break! Stand up and do neck stretches'
                    };
                    main.textContent = (sevLabel[data.severity] || '') + ' forward head posture detected';
                    sub.textContent = sevTip[data.severity] || 'Fix your posture';
                    wrapper.classList.add(data.severity);

                    badgeHtml += '<span class="badge sev-' + data.severity + '">' +
                        data.severity.toUpperCase() + '</span>';

                } else if (data.warning_remaining !== null) {
                    dot.className = 'status-dot warning';
                    main.textContent = 'Posture drifting... alert in ' + data.warning_remaining + 's';
                    sub.textContent = warningTips[tipIndex % warningTips.length];
                    if (data.warning_remaining < 1) tipIndex++;
                    wrapper.classList.add('warning');

                } else {
                    dot.className = 'status-dot good';
                    const gm = getGoodMessage(data.good_posture_seconds);
                    main.textContent = gm.main;
                    sub.textContent = gm.sub;
                    wrapper.classList.add('good');
                    card.classList.add('great');

                    if (data.good_posture_seconds >= 30) {
                        badgeHtml += '<span class="badge streak">' +
                            formatTime(data.good_posture_seconds) + ' streak</span>';
                    }
                }

                badges.innerHTML = badgeHtml;

                // Deviation meter
                const devScore = Math.min(data.deviation_score * 3, 1.0);
                devFill.style.width = (devScore * 100) + '%';
                if (devScore < 0.3) devFill.style.background = '#30d158';
                else if (devScore < 0.6) devFill.style.background = '#ffd60a';
                else devFill.style.background = '#ff3b30';

            } catch (e) {}
        }

        document.addEventListener('keydown', (e) => {
            if (e.target.tagName === 'INPUT') return;
            if (showingResult && (e.key === 'Enter' || e.key === 'Escape')) { dismissResult(); return; }
            if (e.key === 'c' || e.key === 'C') calibrate();
            if (e.key === 'r' || e.key === 'R') resetCalibration();
        });

        setInterval(pollStatus, 300);
    </script>
</body>
</html>
"""


if __name__ == "__main__":
    print("=" * 50)
    print("  Turtle Neck Detector - Web")
    print("=" * 50)
    print()
    print("Open http://localhost:8080 in your browser")
    print()
    app.run(host="0.0.0.0", port=8080, debug=False, threaded=True)
