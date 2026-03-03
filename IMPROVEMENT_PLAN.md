# Turtle Neck Detector - Improvement Plan & OKR

> Living document. Updated as work progresses.
> Last updated: 2026-03-03

---

## Current State (v0.1 MVP)

### What Works
- [x] Menu bar app (LSUIElement, no Dock icon)
- [x] Live camera preview with skeleton overlay
- [x] Face landmarks fallback (when body pose fails)
- [x] Calibration flow (30 samples, CVA validation)
- [x] Score display (0-100) + severity grading
- [x] Menu bar score (1-min rolling average)
- [x] macOS notifications on sustained bad posture
- [x] Camera rotation handling (Insta360 Link 2 portrait → landscape)

### What Doesn't Work Well
- [ ] Bad posture detection accuracy is poor (face-based CVA estimation)
- [ ] Body pose detection fails (shoulders not visible enough for Vision)
- [ ] CVA thresholds don't match clinical literature
- [ ] No long-term data persistence (session-only)
- [ ] No exercise guidance
- [ ] Notifications are basic (no escalation, no positive reinforcement)

---

## OKR Framework

### Objective 1: Accurate Posture Detection
> "The app reliably detects forward head posture within clinically meaningful ranges"

| Key Result | Metric | Current | Target | How to Measure |
|------------|--------|---------|--------|----------------|
| KR1.1 | Detection sensitivity | ~30% | >85% | Lean forward intentionally → app detects within 3s |
| KR1.2 | False positive rate | Unknown | <10% | Good posture held 5min → no false alerts |
| KR1.3 | CVA estimation accuracy | ±20° | ±8° | Compare app CVA vs manual measurement from screenshot |
| KR1.4 | Score responsiveness | Sluggish | <2s lag | Time from posture change to score change |

### Objective 2: Clinically Meaningful Feedback
> "Feedback matches evidence-based posture correction protocols"

| Key Result | Metric | Current | Target | How to Measure |
|------------|--------|---------|--------|----------------|
| KR2.1 | CVA thresholds match literature | Off by 15°+ | Within 5° of clinical | Compare with published CVA ranges |
| KR2.2 | Smart alert (sustained only) | 5s fixed | 3-5min sustained | Bad posture <2min → no alert; >3min → alert |
| KR2.3 | Positive reinforcement ratio | 0% positive | >60% positive msgs | Count positive vs negative notifications per session |
| KR2.4 | Alert habituation rate | N/A | <20% ignore rate by week 4 | User engagement with notifications over time |

### Objective 3: Long-term Posture Improvement
> "Users show measurable CVA improvement over 6-8 weeks"

| Key Result | Metric | Current | Target | How to Measure |
|------------|--------|---------|--------|----------------|
| KR3.1 | CVA trend tracking | None | Daily/weekly averages stored | Data persisted in SQLite/file |
| KR3.2 | Exercise guidance | None | 3 core exercises with instructions | In-app exercise cards |
| KR3.3 | Session history | None | 30-day rolling history | Viewable in settings/stats |
| KR3.4 | Break reminders | None | Every 20-30min of sitting | Timer-based + posture-aware |

### Objective 4: Technical Excellence
> "Vision pipeline is optimized and future-proof"

| Key Result | Metric | Current | Target | How to Measure |
|------------|--------|---------|--------|----------------|
| KR4.1 | CPU usage (monitoring) | Unknown | <5% avg | Activity Monitor during 10min session |
| KR4.2 | 3D pose support | No | Yes (macOS 14+) | Feature flag, graceful fallback |
| KR4.3 | Detection pipeline | Sequential | Batched requests | body+face in single perform() call |
| KR4.4 | Test coverage | 67 unit tests | +20 integration tests | Test detection accuracy with saved frames |

---

## Implementation Phases

### Phase 1: Detection Accuracy (Priority: CRITICAL)
> Goal: KR1.1-1.4, KR2.1

**Status: IN PROGRESS**

#### 1.1 Fix CVA Thresholds to Match Clinical Literature ✅ DONE
- **File**: `PostureAnalyzer.swift`
- **Was**: Good(>50°) / Mild(38-50°) / Moderate(25-38°) / Severe(<25°)
- **Now**: Good(>50°) / Mild(44-50°) / Moderate(40-44°) / Severe(<40°)
- [x] Updated `cvaMild` 38→44, `cvaModerate` 25→40
- [x] Updated `cvaToScore()` with piecewise linear mapping matching clinical ranges
- [x] Face CVA baseline adjusted to 56° (clinical normal)

#### 1.2 Batch Vision Requests (Body + Face Simultaneous) ✅ DONE
- **File**: `VisionPoseDetector.swift`
- **Was**: Sequential (body → fail → face, 2 separate handler.perform calls)
- **Now**: Single `handler.perform([bodyReq, faceReq])` with best-result selection
- [x] Both requests created and performed in single call
- [x] Prefer body pose, fallback to face
- [x] `faceCaptureQuality < 0.3` filter for low-quality detections

#### 1.3 Pass Image Orientation to Vision Handler
- **File**: `VisionPoseDetector.swift` + `CameraManager.swift`
- **Current**: Software rotation via CIImage.oriented(.left) → new CGImage → Vision
- **Action**: Pass raw image + orientation hint to VNImageRequestHandler
- [ ] Option A: `VNImageRequestHandler(cgImage: rawImage, orientation: .left)`
- [ ] Option B: Keep software rotation for preview, orientation hint for Vision
- [ ] Benchmark: does this improve body pose detection rate?

#### 1.4 Improve Face-Based CVA Estimation
- **File**: `VisionPoseDetector.swift`
- **Current**: 3 signals (Y drop, size increase, pitch) with linear mapping
- **Action**: Tune weights based on real testing + add yaw signal
- [ ] Wire `calibrateFaceBaseline()` into calibration flow ✅ DONE
- [ ] Add debug logging to see actual signal values during testing
- [ ] Test with multiple postures and record signal→CVA mapping
- [ ] Tune weights based on empirical data
- [ ] Consider adding `yaw` as secondary signal (lateral head position)

#### 1.5 VNDetectHumanBodyPose3DRequest (macOS 14+) ✅ DONE
- **File**: `VisionPoseDetector.swift`
- **Key finding**: 3D pose WORKS even when 2D pose fails! Provides real Z-depth.
- [x] Runtime `#available(macOS 14.0, *)` check
- [x] 3D pose extraction with centerHead, centerShoulder, leftShoulder, rightShoulder
- [x] True CVA from 3D: `atan2(verticalDist, forwardDist)`
- [x] Fallback chain: 3D pose → 2D pose → face landmarks
- [x] 2D skeleton projection via `pointInImage()` for display
- [x] All three requests batched in single `handler.perform()`

#### 1.6 Add Detection Accuracy Test Suite
- **File**: New `test_detection_accuracy.swift`
- **Action**: Save reference frames + expected CVA, run detection, compare
- [ ] Save 5-10 reference frames at known postures (good, mild, moderate, severe)
- [ ] Write test that runs detection on each frame
- [ ] Assert CVA is within expected range for each posture
- [ ] Track accuracy over code changes

---

### Phase 2: Clinical Feedback System (Priority: HIGH)
> Goal: KR2.1-2.4

**Status: NOT STARTED**

#### 2.1 Smart Threshold-Based Alerts
- **File**: `PostureAnalyzer.swift`, `PostureEngine.swift`
- **Current**: Alert after 5s of bad posture, 60s cooldown
- **Clinical**: Only alert after 3-5 min sustained FHP
- [ ] Change `sustainedDurationSec` from 5 → 180 (3 minutes)
- [ ] Add warning stages: 1min=subtle indicator, 3min=gentle alert, 10min=strong alert
- [ ] Respect macOS Focus Mode (check `UNNotificationSetting`)

#### 2.2 Escalating Notification Severity
- **File**: `NotificationService.swift`, `MenuBarView.swift`
- **Current**: Single notification type with 60s cooldown
- **Action**: 3-tier escalation system
- [ ] Tier 1 (1 min bad): Menu bar icon turns yellow (no notification)
- [ ] Tier 2 (3 min bad): Gentle notification with correction tip
- [ ] Tier 3 (10+ min bad): Urgent notification suggesting break + exercise
- [ ] Cooldown: 5 min between Tier 2, 15 min between Tier 3

#### 2.3 Positive Reinforcement System
- **File**: `FeedbackEngine.swift`, `NotificationService.swift`
- **Current**: Good posture messages only shown in UI (not as notifications)
- **Action**: Celebrate good posture milestones via notification
- [ ] Notify at 15min, 30min, 60min good posture streaks
- [ ] Frame positively: "Great job! 30 minutes of good posture"
- [ ] Track daily "good posture minutes" as primary user metric
- [ ] Show daily good-posture percentage in menu bar tooltip

#### 2.4 Micro-Break Reminders
- **File**: New `BreakManager.swift`, `PostureEngine.swift`
- **Action**: 20-30 min sitting detection → suggest active break
- [ ] Track continuous sitting duration (camera active = sitting)
- [ ] After 25 min: "Time for a 30-second stretch break!"
- [ ] Suggest specific quick exercise (rotating through chin tuck, shoulder rolls, etc.)
- [ ] Detect when user returns from break (camera resumes after absence)

---

### Phase 3: Long-term Tracking & Exercises (Priority: MEDIUM)
> Goal: KR3.1-3.4

**Status: NOT STARTED**

#### 3.1 Data Persistence Layer
- **File**: New `PostureDataStore.swift`
- **Current**: All data is session-only (lost on quit)
- **Action**: SQLite or JSON file for historical data
- [ ] Store per-session: avg CVA, min CVA, duration, good-posture-%, timestamp
- [ ] Store daily aggregates: avg score, total monitored time, good posture %
- [ ] Store weekly CVA trend for progress tracking
- [ ] Migration path from UserDefaults calibration data

#### 3.2 Progress Dashboard
- **File**: New `StatsView.swift`, update `MenuBarView.swift`
- **Action**: Show CVA trend over time
- [ ] Today's stats: score, time monitored, good posture %
- [ ] 7-day trend: daily average CVA line chart
- [ ] 30-day overview: weekly averages, improvement indicator
- [ ] "Your CVA improved 5° this month" milestone notifications

#### 3.3 Exercise Guide
- **File**: New `ExerciseView.swift`, `ExerciseManager.swift`
- **Action**: In-app exercise cards with instructions
- [ ] 3 core exercises: Chin Tuck, Wall Angels, Scapular Retraction
- [ ] Each: illustration/description, sets/reps, duration
- [ ] Personalized by severity: mild=chin tucks only, severe=full routine
- [ ] Optional: chin tuck form verification via camera (face Y + pitch tracking)

#### 3.4 Streak System with Forgiveness
- **File**: `FeedbackEngine.swift`, `PostureDataStore.swift`
- **Current**: Session-only streak timer
- **Action**: Multi-day streak with forgiveness
- [ ] "Good posture day" = >60% good posture during monitored time
- [ ] Streak counts consecutive good days
- [ ] 1 "free pass" per week (miss 1 day without breaking streak)
- [ ] Show streak in menu bar view

---

### Phase 4: Technical Optimization (Priority: LOW)
> Goal: KR4.1-4.4

**Status: NOT STARTED**

#### 4.1 Performance Profiling
- [ ] Measure CPU usage with Instruments during 10-min session
- [ ] Profile Vision request latency (body vs face vs 3D)
- [ ] Optimize: skip analysis when app is not frontmost + no alerts pending
- [ ] Memory profiling: ensure no frame leaks

#### 4.2 Camera Session Optimization
- **File**: `CameraManager.swift`
- [ ] Consider snapshot mode when popover is closed (1 frame/3s instead of continuous)
- [ ] Resume continuous when popover opens (for live preview)
- [ ] Handle camera disconnect/reconnect gracefully

#### 4.3 Launch at Login
- [ ] Add `SMAppService.mainApp.register()` for login item
- [ ] Settings toggle to enable/disable
- [ ] Auto-start monitoring on launch (optional setting)

#### 4.4 Expanded Test Suite
- [ ] Integration tests: calibration → monitoring → detection → notification
- [ ] Saved frame tests for detection accuracy regression
- [ ] Performance benchmarks (detection latency per frame)

---

## Measurement Protocol

### Weekly Review Checklist
Every week, measure and record:

1. **Detection accuracy test**: Run through 4 postures (good/mild/moderate/severe), record detected CVA for each
2. **False positive count**: 5-min good posture session → count false bad-posture alerts
3. **Response latency**: Time from posture change to score update
4. **CPU usage**: 10-min monitoring session average
5. **User satisfaction**: Subjective rating 1-5 (does it feel accurate?)

### Recording Format
```
## Week of YYYY-MM-DD
- Detection: Good=__° Mild=__° Moderate=__° Severe=__°
- False positives in 5min: __
- Response lag: __s
- CPU avg: __%
- Satisfaction: _/5
- Notes: ...
```

---

## Progress Log

### 2026-03-03 (Day 1)
- [x] Built MVP menu bar app with face fallback detection
- [x] Wired `calibrateFaceBaseline()` into PostureEngine
- [x] Fixed PostureAnalyzer for face fallback (CVA-based instead of distance-based)
- [x] Improved face CVA estimation weights (12/6/5 for Y/size/pitch)
- [x] Reduced smoothing window 5→3 frames for faster response
- [x] Added `resetFaceBaseline()` for calibration reset
- [x] Created this improvement plan
- [x] Phase 1.1: CVA thresholds updated to clinical literature (Mild 44°, Moderate 40°)
- [x] Phase 1.1: Score mapping rewritten as piecewise-linear matching clinical ranges
- [x] Phase 1.2: Batched body+face Vision requests in single perform() call
- [x] Phase 1.2: Added faceCaptureQuality filter (<0.3 rejected)
- [x] Phase 1.4: Added debug logging for CVA signal diagnosis
- [x] Face CVA baseline set to 56° (clinical normal range)
- [x] Phase 1.5: 3D body pose (macOS 14+) implemented — works even when 2D fails!
- [x] Phase 1.5: Fallback chain: 3D pose → 2D pose → face landmarks
- [x] Side-by-side Python (MediaPipe) vs Swift (Apple Vision 3D) CVA comparison tool
- [x] Discovered Apple Vision 3D monocular Z-depth is compressed vs real displacement
- [x] Implemented relative ratio-based CVA: calibration stores rawFwd/vert ratio baseline
- [x] CVA mapping calibrated from empirical Python comparison data
- [x] Menu bar score synced with popover score (both show real-time postureScore)
- [x] Ad-hoc code signing for persistent camera permission
- [x] Build script (build.sh) with automatic code signing
- **Results** (post-calibration):
  - Good posture: CVA ~55° → score ~80 (Good)
  - Mild forward: CVA ~44° → score ~50 (Mild)
  - Turtle neck: CVA ~30° → score ~20 (Severe)
  - Extreme: CVA ~25° → score ~12 (Severe)
- **Next**: Phase 1.6 (test suite) + Phase 2 (clinical feedback)

---

## Architecture Reference

```
TurtleNeckDetector/
├── TurtleNeckDetectorApp.swift    # @main, MenuBarExtra
├── Core/
│   ├── PostureEngine.swift         # Orchestrator (timer→camera→vision→UI)
│   ├── CameraManager.swift         # AVCaptureSession, frame rotation
│   ├── VisionPoseDetector.swift    # Body pose + face fallback detection
│   ├── PostureAnalyzer.swift       # CVA evaluation, severity, thresholds
│   └── CalibrationManager.swift    # 30-sample calibration, validation
├── Models/
│   ├── PostureMetrics.swift        # Immutable measurement struct
│   ├── CalibrationData.swift       # Codable baseline
│   ├── PostureState.swift          # Current state + Severity enum
│   └── CameraPosition.swift        # Center/Left/Right
├── Services/
│   ├── NotificationService.swift   # macOS notifications + cooldown
│   └── FeedbackEngine.swift        # Dynamic messages, streaks
└── Views/
    ├── MenuBarView.swift           # Main popover UI
    ├── CameraPreviewView.swift     # Live preview + skeleton
    ├── PostureScoreView.swift      # Score gauge (0-100)
    ├── CalibrationView.swift       # Calibration progress
    └── SettingsView.swift          # Camera position, interval
```

## Clinical Reference

### CVA Severity (Clinical Literature)
| CVA | Classification | For Score Mapping |
|-----|---------------|-------------------|
| >53° | Normal | Score 85-100 |
| 50-53° | Borderline | Score 70-85 |
| 44-50° | Mild FHP | Score 50-70 |
| 40-44° | Moderate FHP | Score 30-50 |
| <40° | Severe FHP | Score 0-30 |

### Evidence-Based Exercise Protocol
| Exercise | Protocol | For Severity |
|----------|----------|-------------|
| Seated chin tuck | 10 reps, 5s hold, every hour | All |
| Supine chin tuck | 3x10 reps, 5-10s hold, daily | Mild+ |
| Wall angels | 3x10 reps, daily | Moderate+ |
| Scapular retraction | 5s hold x 10 reps, daily | Moderate+ |
| Doorway pec stretch | 30s x 3 positions, daily | Severe |
| Thoracic extension | 60-90s on foam roller, daily | Severe |

### Key Medical Facts
- Each 1 inch of forward head = +4.5kg cervical spine load
- Normal head weight: ~5kg → Severe FHP: 20-25kg load
- Awareness alone does NOT fix FHP — muscle strengthening is required
- Correction timeline: 6-8 weeks for measurable CVA improvement
- Discrete (threshold) feedback > continuous feedback for compliance
- Positive reinforcement > negative alerts for long-term adherence
