# Calibration Overhaul: Relative Baseline-Deviation Scoring

## Context

The current scoring system uses **absolute CVA thresholds** (CVA 20->score 5, CVA 65->score 98) hard-coded to one specific camera+monitor setup. Different webcam positions, distances, and angles produce wildly different raw CVA values -- making the app useless for anyone else. Research into commercial posture apps (PostureCV, SitApp, Upright Go) and academic papers confirms all successful consumer posture apps use **relative baseline-deviation scoring**, never absolute clinical thresholds.

**Goal**: Any user with a fixed desktop monitor setup can calibrate and get accurate turtle neck detection, regardless of their specific camera model/position/distance.

## Files to Modify (6 files)

1. `TurtleneckCoach/Models/CalibrationData.swift` -- add quality metadata
2. `TurtleneckCoach/Core/CalibrationManager.swift` -- median aggregation, variance-based quality gate
3. `TurtleneckCoach/Core/PostureAnalyzer.swift` -- replace absolute scoring with relative scoring
4. `TurtleneckCoach/Models/PostureState.swift` -- add `score` field
5. `TurtleneckCoach/Core/PostureEngine.swift` -- use score-based hysteresis
6. `test_logic.swift` -- update tests

## Phase 1: CalibrationData Model

**File**: `CalibrationData.swift`

Add three new fields with backward-compatible decoding:

- `cvaStdDev: CGFloat` -- standard deviation of CVA samples during calibration
- `landmarkConfidence: CGFloat` -- fraction of valid samples (0.0-1.0)
- `schemaVersion: Int` -- 1 = old absolute, 2 = new relative

Add to `init(from decoder:)` with `decodeIfPresent` defaults: `cvaStdDev ?? 0`, `landmarkConfidence ?? 0`, `schemaVersion ?? 1`. Add to memberwise `init` with defaults.

## Phase 2: CalibrationManager -- Median + Variance Gate

**File**: `CalibrationManager.swift`

### 2a. Switch from MEAN to MEDIAN aggregation

Add a `median()` helper. Replace all `reduce(0, +) / n` averaging with median for: `neckEarAngle`, `earShoulderDistance*`, `eyeShoulderDistance*`, `headForwardRatio`, `headTiltAngle`, `shoulderEvenness`, `headPitch`, `baselineFaceSize`, `forwardDepth`, `irisGazeOffset`.

### 2b. Compute cvaStdDev and landmarkConfidence

After computing median CVA, compute variance/stdDev of CVA samples and confidence as `valid.count / samples.count`.

### 2c. Replace absolute CVA gate with variance-based quality gate

**Remove**: `minCalibrationCVA = 40.0` and the `avgCVA < Self.minCalibrationCVA` check.

**Replace with** three quality checks:
1. `stdDev > 3.0` -> "Too much movement. Hold still during calibration."
2. `confidence < 0.7` -> "Couldn't detect your pose reliably. Check lighting and camera angle."
3. `medianCVA < 5.0` -> "Couldn't measure your neck angle. Make sure face and shoulders are visible."

Pass `cvaStdDev`, `landmarkConfidence`, `schemaVersion: 2` to CalibrationData init.

## Phase 3: PostureAnalyzer -- Relative Scoring

**File**: `PostureAnalyzer.swift`

### 3a. New `relativeScore()` (replaces `cvaToScore`)

Deviation-based: `deviation = max(0, (baselineCVA - currentCVA) / baselineCVA)`. Maps 0% deviation -> 95, ~15% -> ~72, ~30% -> ~50, 50%+ -> ~20. Simple linear: `score = 95 - deviation * 150`, clamped to 2-98.

### 3b. New `compositeRelativeScore()`

Fuses CVA deviation (primary, ~75% weight) with auxiliary signals:
- Pitch delta penalty: up to 15 points for increased head pitch vs baseline
- Face size change penalty: up to 10 points for face growing (leaning forward)
- `lookingDown` classification: recover 50% of pitch penalty (CVA drop is from neck flexion, not FHP)

### 3c. Update `classifySeverity` signature

Change from `classifySeverity(_ cva:, mode:)` to `classifySeverity(score:, mode:)`:

```swift
static func classifySeverity(score: Int, mode: SensitivityMode) -> Severity {
    if score >= mode.goodThreshold { return .good }
    if score >= mode.correctionThreshold { return .correction }
    if score >= mode.badThreshold { return .bad }
    return .away
}
```

### 3d. Update `evaluate()` to use relative scoring

- After computing `adjustedCVA` and `classification`, call `compositeRelativeScore()` to get `computedScore`
- Use `classifySeverity(score: computedScore, mode:)` for severity
- Pass `score: computedScore` to all PostureState constructors
- Face fallback path: use `relativeScore(currentCVA:baselineCVA:)` directly

### 3e. Remove absolute CVA helpers

Delete: `cvaToScore()`, `cvaGood()`, `cvaCorrection()`, `cvaBad()`, `cvaForScoreThreshold()`. These are fully replaced by score-based thresholds from `SensitivityMode` (which already exist and need no changes).

## Phase 4: PostureState -- Add Score Field

**File**: `PostureState.swift`

Add `score: Int` field to `PostureState`. Default in `.initial`: `score: 90`. Update all PostureState constructors in `PostureAnalyzer.evaluate()` to include score.

## Phase 5: PostureEngine -- Score-Based Hysteresis

**File**: `PostureEngine.swift`

### 5a. Replace `postureScore` computed property

```swift
// OLD: PostureAnalyzer.cvaToScore(postureState.currentCVA)
// NEW:
var postureScore: Int { postureState.score }
```

### 5b. Convert hysteresis from absolute CVA to score-based

Replace `cvaBoundaryBuffer: CGFloat = 2.0` / `cvaTransitionCrossover: CGFloat = 3.0` with:
- `scoreBoundaryBuffer: Int = 3` (dead zone)
- `scoreTransitionCrossover: Int = 5` (must cross threshold by 5 points)

Update `shouldStartTransition(from:toward:cva:)` -> `shouldStartTransition(from:toward:score:)`:
- Compare score against `transitionScoreThreshold()` instead of CVA against absolute CVA thresholds

Update `transitionThreshold()` -> `transitionScoreThreshold()`:
- Return `mode.goodThreshold` / `mode.correctionThreshold` / `mode.badThreshold` directly (these are already score-based integers)

Update `updateMenuBarSeverity` signature: `currentCVA:` -> `currentScore:`. Update call site at line ~829.

## Phase 6: Test Updates

**File**: `test_logic.swift`

- Update `classifySeverity` tests to use `score:` parameter
- Add `relativeScore()` tests:
  - 0% deviation (current == baseline) -> ~95
  - 15% deviation -> ~72
  - 30% deviation -> ~50
  - 50% deviation -> ~20
- Add `compositeRelativeScore()` tests with `lookingDown` classification variant
- Add calibration variance gate tests (stdDev > 3 = invalid, stdDev < 3 = valid)

## Verification

1. `./build.sh` -- compiles without errors
2. Launch app -> calibrate with good posture -> score starts ~90-95
3. Lean forward gradually -> score drops smoothly, severity transitions good->correction->bad
4. Return to upright -> score recovers to 90+, severity returns to good
5. Recalibrate at different distance/angle -> same behavior (camera-invariant)
6. Check debug log (`/tmp/turtle_cvadebug.log`) for relative scores
