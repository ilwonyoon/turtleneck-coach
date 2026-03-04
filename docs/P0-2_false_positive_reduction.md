# P0-2: False Positive Notification Reduction

## Problem

Notifications fire during normal activities — standing up, reaching for objects, touching face, yawning. This causes notification fatigue and will make users disable the app.

## What's Already Done

- ✅ Alert cooldown (30s/150s/300s configurable via NotificationFrequency)
- ✅ Camera confidence filter (low confidence detections rejected)
- ✅ Head yaw filter (looking sideways → classifier returns .unknown)
- ✅ FHP vs looking-down classification (50% CVA recovery for neck flexion)
- ✅ EMA smoothing on CVA (adaptive alpha, aggressive on large jumps)
- ✅ Menu bar severity hold timers (worsen 1s initial, improve 2s initial)
- ✅ Yaw-based CVA freeze (MediaPipe freezes CVA when yaw unreliable)

## What's Missing

No check for:
1. How long bad posture has been sustained before first notification
2. Whether user is in motion (reaching, stretching)
3. Whether face size changed rapidly (standing/sitting)
4. Whether face landmarks are jittering (face touch/glasses)
5. Whether hand is near face (chin resting)

## Architecture

**Key principle**: All suppression is a **notification gate** only. Detection, scoring, and UI severity all continue unchanged. Only `notificationService.notify()` calls are gated.

```
analyzeLatestFrame()
  → PostureAnalyzer.evaluate() → postureState updated (UNCHANGED)
  → updateMenuBarSeverity() → held severity updated (UNCHANGED)
  → [NEW] suppression gate checks
  → if NOT suppressed → notificationService.notify()
```

### Current Notification Trigger (PostureEngine.swift lines 440-450)

```swift
// Current code — replace this block
let held = menuBarSeverity
if held == .correction || held == .bad {
    let msg = NotificationService.message(for: held)
    notificationService.notify(
        title: "PT Turtle",
        message: msg,
        severity: held
    )
}
```

### New Notification Trigger (replacement)

```swift
let held = menuBarSeverity
if held == .correction || held == .bad {
    let shouldSuppress =
        checkSustainedDurationGate()
        || checkMotionSuppression(currentCVA: smoothed)
        || checkScaleChangeSuppression(currentFaceSize: metrics.faceSizeNormalized)
        || checkLandmarkJitterSuppression(nosePosition: result.joints.nose)
        || checkWristProximitySuppression(joints: result.joints)

    if !shouldSuppress {
        let msg = NotificationService.message(for: held)
        notificationService.notify(
            title: "PT Turtle",
            message: msg,
            severity: held
        )
    }
} else {
    sustainedBadStart = nil
}
```

## Five Suppression Filters

### Filter 1: Sustained Duration Gate (MOST IMPACTFUL)

**Catches**: All transient bad posture — reaching, yawning, brief slouch, any short dip

**Logic**: Bad posture must persist for 25 seconds continuously before any notification fires for that episode.

```swift
// Properties
private var sustainedBadStart: Date? = nil
private let sustainedBadThreshold: TimeInterval = 25.0

// Check method
private func checkSustainedDurationGate() -> Bool {
    let held = menuBarSeverity
    guard held == .correction || held == .bad else {
        sustainedBadStart = nil
        return false  // good posture, no suppression needed
    }
    let now = Date()
    if sustainedBadStart == nil {
        sustainedBadStart = now
    }
    guard let start = sustainedBadStart else { return true }
    // Suppress if duration < threshold
    return now.timeIntervalSince(start) < sustainedBadThreshold
}
```

**Reset**: When severity returns to good. Also reset in `stopMonitoring()` and after calibration completes.

---

### Filter 2: Motion Filter (CVA velocity)

**Catches**: Reaching for objects, stretching, adjusting position — any rapid head/body movement

**Logic**: Track frame-to-frame CVA delta. If delta > 5° → motion detected → suppress. Require 3 consecutive low-delta frames to clear.

```swift
// Properties
private var previousSmoothedCVA: CGFloat? = nil
private var motionFrameCount: Int = 0
private let motionCVAThreshold: CGFloat = 5.0
private let motionClearFrames: Int = 3

// Check method
private func checkMotionSuppression(currentCVA: CGFloat) -> Bool {
    defer { previousSmoothedCVA = currentCVA }
    guard let prev = previousSmoothedCVA else { return false }
    let delta = abs(currentCVA - prev)
    if delta > motionCVAThreshold {
        motionFrameCount = 0  // reset: motion detected
        return true
    }
    if motionFrameCount < motionClearFrames {
        motionFrameCount += 1
        return true  // still clearing motion
    }
    return false
}
```

---

### Filter 3: Scale Change (standing/sitting)

**Catches**: Standing up, sitting down, leaning way forward/backward

**Logic**: Track face size frame-to-frame. If relative change > 15% → hold notifications for 5 seconds.

```swift
// Properties
private var previousFaceSize: CGFloat? = nil
private var scaleChangeHoldUntil: Date? = nil
private let scaleChangeThreshold: CGFloat = 0.15
private let scaleChangeHoldDuration: TimeInterval = 5.0

// Check method
private func checkScaleChangeSuppression(currentFaceSize: CGFloat) -> Bool {
    let now = Date()
    defer { previousFaceSize = currentFaceSize }

    // Check if we're in a hold period
    if let holdUntil = scaleChangeHoldUntil, now < holdUntil {
        return true
    }
    scaleChangeHoldUntil = nil

    guard let prevSize = previousFaceSize, prevSize > 0 else { return false }
    let relativeChange = abs(currentFaceSize - prevSize) / prevSize
    if relativeChange > scaleChangeThreshold {
        scaleChangeHoldUntil = now.addingTimeInterval(scaleChangeHoldDuration)
        return true
    }
    return false
}
```

---

### Filter 4: Landmark Jitter (face touching/glasses)

**Catches**: Touching face, adjusting glasses, scratching, brief hand-to-face contact

**Logic**: Track nose position over a 3-second window. If position variance spikes above threshold → hold notifications for 3 seconds.

```swift
// Properties
private var recentNosePositions: [(date: Date, point: CGPoint)] = []
private var jitterHoldUntil: Date? = nil
private let jitterVarianceThreshold: CGFloat = 0.003
private let jitterHoldDuration: TimeInterval = 3.0

// Check method
private func checkLandmarkJitterSuppression(nosePosition: CGPoint) -> Bool {
    let now = Date()

    // Check if we're in a hold period
    if let holdUntil = jitterHoldUntil, now < holdUntil {
        return true
    }
    jitterHoldUntil = nil

    // Track nose positions (keep ~3 second window)
    recentNosePositions.append((date: now, point: nosePosition))
    let cutoff = now.addingTimeInterval(-3.0)
    recentNosePositions.removeAll { $0.date < cutoff }

    guard recentNosePositions.count >= 5 else { return false }

    // Compute position variance
    let count = CGFloat(recentNosePositions.count)
    let avgX = recentNosePositions.map(\.point.x).reduce(0, +) / count
    let avgY = recentNosePositions.map(\.point.y).reduce(0, +) / count
    let variance = recentNosePositions.reduce(CGFloat(0)) { sum, entry in
        let dx = entry.point.x - avgX
        let dy = entry.point.y - avgY
        return sum + dx * dx + dy * dy
    } / count

    if variance > jitterVarianceThreshold {
        jitterHoldUntil = now.addingTimeInterval(jitterHoldDuration)
        return true
    }
    return false
}
```

---

### Filter 5: Wrist Proximity (chin on hand)

**Catches**: Resting chin on hand, propping head up with arm

**Logic**: Extract wrist joints from Vision body pose (already available in VNHumanBodyPoseObservation as `.leftWrist`/`.rightWrist`, just not currently read). If distance(wrist, nose) < threshold → suppress.

```swift
// Properties
private let wristFaceDistanceThreshold: CGFloat = 0.12  // normalized (0-1) distance

// Check method
private func checkWristProximitySuppression(joints: DetectedJoints) -> Bool {
    guard let leftWrist = joints.leftWrist else {
        guard let rightWrist = joints.rightWrist else { return false }
        return hypot(rightWrist.x - joints.nose.x, rightWrist.y - joints.nose.y) < wristFaceDistanceThreshold
    }
    guard let rightWrist = joints.rightWrist else {
        return hypot(leftWrist.x - joints.nose.x, leftWrist.y - joints.nose.y) < wristFaceDistanceThreshold
    }
    let distL = hypot(leftWrist.x - joints.nose.x, leftWrist.y - joints.nose.y)
    let distR = hypot(rightWrist.x - joints.nose.x, rightWrist.y - joints.nose.y)
    return distL < wristFaceDistanceThreshold || distR < wristFaceDistanceThreshold
}
```

**Requires**: Wrist joint extraction (see below).

---

## Wrist Joint Extraction

### `VisionPoseDetector.swift` — DetectedJoints struct

Add optional wrist properties (with defaults so existing call sites don't break):

```swift
struct DetectedJoints {
    let nose: CGPoint
    let neck: CGPoint
    let leftEar: CGPoint
    let rightEar: CGPoint
    let leftEye: CGPoint
    let rightEye: CGPoint
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftEarConfidence: Float
    let rightEarConfidence: Float
    var leftWrist: CGPoint? = nil      // NEW
    var rightWrist: CGPoint? = nil     // NEW
    var faceMesh: FaceMeshData? = nil
    // ... rest unchanged
}
```

### `VisionPoseDetector.swift` — extractBodyResult()

After extracting shoulders, add optional wrist extraction:

```swift
let lWristP = try? observation.recognizedPoint(.leftWrist)
let rWristP = try? observation.recognizedPoint(.rightWrist)
```

Pass to DetectedJoints constructor:

```swift
leftWrist: lWristP.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) },
rightWrist: rWristP.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
```

### `MediaPipeClient.swift` — resultToJoints()

No wrist data from current MediaPipe protocol. Existing call sites use default `nil` values for wrist fields. No changes needed unless wrist data is later added to the Python server protocol.

**Note**: Do NOT add wrists to `allPoints` or `connections` in DetectedJoints — they are below the camera frame in typical use and would create confusing skeleton overlay lines.

---

## State Reset

### In `stopMonitoring()`

```swift
// Reset suppression state
sustainedBadStart = nil
previousSmoothedCVA = nil
motionFrameCount = 0
previousFaceSize = nil
scaleChangeHoldUntil = nil
recentNosePositions.removeAll()
jitterHoldUntil = nil
```

### After calibration completes (in the `if calResult.isValid` block)

```swift
sustainedBadStart = nil
motionFrameCount = motionClearFrames  // don't suppress right after calibration
previousFaceSize = nil
```

---

## Files Changed

| File | Action | Scope |
|------|--------|-------|
| `Core/PostureEngine.swift` | Modify | Add ~15 properties, 5 methods, gate logic, resets |
| `Core/VisionPoseDetector.swift` | Modify | Add wrist fields to DetectedJoints, extract from body pose |
| `Core/MediaPipeClient.swift` | Check | Ensure DetectedJoints init compatibility (defaults handle it) |

## Verification

```bash
./build.sh
open TurtleNeckDetector.app
```

Test each filter:

| Test | Expected Result |
|------|----------------|
| Stand up quickly while monitoring | No notification |
| Reach across desk for something | No notification |
| Touch face / adjust glasses | No notification |
| Yawn or stretch (2-3 seconds) | No notification |
| Rest chin on hand (if body pose active) | No notification |
| Sit with bad posture < 25 seconds | No notification |
| Sit with bad posture > 30 seconds | Notification fires |
| Sustained genuine slouch | Notification fires (duration gate passed) |

**Key validation**: Ensure genuine sustained bad posture still triggers alerts. The duration gate (25s) + existing cooldown (30-300s) should not over-suppress.
