# Turtleneck Coach — Product Backlog PRD

> Last updated: 2026-03-04

## Priority Levels

- **P0**: Must-have for initial sharing/launch
- **P1**: Important for paid product quality
- **P2**: Nice-to-have, v2+
- **P3**: Future consideration

---

## P0 — Before Sharing

### 1. Onboarding Experience (NEW)

**Problem**: First-time users see the popover cold — no explanation of what the app does, how scoring works, or what to expect.

**Scope**:
- First-run welcome screen explaining the app (1 screen)
- Calibration guidance: "Sit up straight, face the camera" with visual cue
- Brief explanation of score zones (Great/Adjust/Reset) after calibration
- Screen distance check using `faceSizeNormalized` (too close / too far warning)
- Skip option for returning users (persisted via UserDefaults)

**Files to modify**: `TurtleneckCoachApp.swift`, new `OnboardingView.swift`

### 2. False Positive Reduction

**Problem**: Alerts fire during normal activities (reaching, standing, brief movements). This causes notification fatigue.

**What's already done**:
- ✅ Alert cooldown (30s/150s/300s configurable)
- ✅ Camera confidence filter
- ✅ Head yaw filter (sideways = suppress)
- ✅ Calibration baseline comparison
- ✅ FHP vs looking-down classification
- ✅ EMA smoothing on CVA
- ✅ Menu bar severity hold timers (worsen 1s, improve 2s)

**What's needed**:

#### 2a. Duration Filter (sustained bad posture gate)
Currently notifications fire as soon as `menuBarSeverity` transitions to correction/bad. Add a sustained-bad timer: only notify after bad posture is held for 25-30 seconds continuously.

**Files**: `PostureEngine.swift` — add `sustainedBadPostureStart` tracking before `notificationService.notify()` call (around line 442-449)

#### 2b. Motion Filter (movement = suppress)
Track CVA velocity (frame-to-frame delta). When velocity is high (user reaching, adjusting position), suppress alert evaluation. Static slouch = alert, dynamic movement = ignore.

**Files**: `PostureEngine.swift` — add CVA delta tracking in `analyzeLatestFrame()`

#### 2c. Scale Change Suppress (standing/sitting)
Detect rapid face size changes (standing up, sitting down, leaning way forward/back). Hold alerts for 5-8 seconds after large scale shifts.

**Files**: `PostureEngine.swift` — track `faceSizeNormalized` velocity

---

## P1 — Paid Product Quality

### 3. Alert Message Tone

**Current**: "Head's drifting. Tuck your chin." / "Posture's gone. Sit up, reset."
**Better**: Duration-aware, softer tone. "You've been leaning forward for a while. Let's reset."

**Files**: `NotificationService.swift`, `FeedbackEngine.swift`

### 4. Quick Reset Prompts in Alerts

Add actionable micro-exercise to each notification: "Chin tuck × 5" or "Stand for 10 seconds."

**Files**: `NotificationService.swift` — rotate exercise suggestions per severity

### 5. First-Run Posture Coaching Explainer

After calibration completes, show a brief overlay explaining:
- Green = great posture
- Yellow = minor drift, self-correct
- Orange = sustained bad posture, take action
- How notifications work

**Files**: new view or extension of `CalibrationView.swift`

### 6. Multi-Day Streak

Currently streak is session-only. Persist daily "good posture day" streak in `PostureDataStore`. Show in dashboard.

**Files**: `PostureDataStore.swift`, `DashboardView.swift`

### 7. Privacy Policy Document

Required for any distribution. Create a formal privacy policy:
- No images stored or transmitted
- All processing on-device
- No personal data collected
- Optional iCloud sync stores only aggregate metrics

**Files**: new `docs/PRIVACY.md`, link from Settings

### 8. Landing Page

Simple one-page site for sharing/download link. Can use GitHub Pages or similar.

### 9. Marketing Screenshots

Capture menu bar popover, dashboard, and calibration flow for store/website.

---

## P2 — v2 Features

### 10. Hand-on-Face Detection

Suppress alerts when wrist landmarks are near chin/nose (user resting chin on hand). Requires wrist landmark tracking — currently not extracted from Vision pose.

### 11. Short Gesture Suppress (glasses, face touch)

Brief hand-to-face contact (< 3s) should not trigger false readings. Depends on #10.

### 12. Exercise Library

10-15 posture exercises with simple illustrations or animations:
- Chin tuck, wall angel, thoracic extension, scapular retraction, chest stretch
- Integrated into alert flow and standalone exercise view

### 13. iCloud Sync via CloudKit

Sync session data across devices using CloudKit private database. No login required (uses Apple ID automatically). Requires `PostureDataStore` migration to SwiftData or CloudKit-compatible store.

### 14. Screen Distance Guidance (ongoing)

Beyond onboarding, periodically check face size vs baseline. If user is consistently too close, show a gentle "You're leaning in — try zooming your screen" hint.

---

## P3 — Future

### 15. Pricing & Payment

- One-time purchase: $9.99–$15
- Platform: Paddle or Gumroad for direct sales
- License key validation system
- OR: Mac App Store submission (30% commission, sandbox constraints)

### 16. App Store Submission

Requires: sandbox compliance, App Store review, metadata, screenshots, privacy nutrition label.

### 17. Break Timer / Sitting Duration

Track continuous sitting time. Suggest breaks at configurable intervals (25 min Pomodoro, 45 min, etc.).

### 18. Posture Trend Insights

Weekly summary notification: "Your bad posture time decreased 15% this week."

---

## Status Legend

| Status | Meaning |
|--------|---------|
| ✅ | Already implemented |
| 🔨 | In progress |
| 📋 | Planned, not started |
| ⏸️ | Deferred |

## Current Status

| # | Item | Status |
|---|------|--------|
| 1 | Onboarding | 📋 |
| 2a | Duration filter | 📋 |
| 2b | Motion filter | 📋 |
| 2c | Scale change suppress | 📋 |
| 3 | Alert message tone | 📋 |
| 4 | Quick reset prompts | 📋 |
| 5 | Coaching explainer | 📋 |
| 6 | Multi-day streak | 📋 |
| 7 | Privacy policy | 📋 |
| 8 | Landing page | 📋 |
| 9 | Marketing screenshots | 📋 |
| 10 | Hand-on-face | ⏸️ |
| 11 | Short gesture suppress | ⏸️ |
| 12 | Exercise library | ⏸️ |
| 13 | iCloud sync | ⏸️ |
| 14 | Screen distance (ongoing) | ⏸️ |
| 15 | Pricing & payment | ⏸️ |
| 16 | App Store submission | ⏸️ |
| 17 | Break timer | ⏸️ |
| 18 | Posture trend insights | ⏸️ |
