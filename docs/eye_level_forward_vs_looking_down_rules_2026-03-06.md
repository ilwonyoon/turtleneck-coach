# Eye-Level Forward-Head vs Looking-Down Rules
Date: 2026-03-06
Owner: Track 2
Status: Draft

## 1. Purpose
This document defines a practical rule set for separating `forwardHead` from `lookingDown` in the `eye_level` posture context.

The goal is not to redesign the whole scorer. The goal is to stop obvious `lookingDown` samples from collapsing into `forwardHead` while preserving the current strengths:
- Good posture remains stable.
- Severe forward head posture (FHP) remains easy to detect.
- Desktop and non-eye-level contexts do not regress.

## 2. Problem Statement
Current posture scoring is already usable for:
- stable Good posture
- severe FHP
- some mild/severe FHP separation

The remaining classification gap is this:
- in `eye_level` usage, `lookingDown` often gets classified as `forwardHead`
- once that happens, the score path applies forward-head penalties instead of partial neck-flexion recovery
- the UI then tells the user to "tuck your chin" when the actual problem is "lift your gaze"

This is a product problem, not just a model-labeling problem. Wrong separation changes score, severity timing, and coaching copy.

## 3. Observed Failure Mode
### 3.1 What is working
- Good samples are stable after calibration.
- Severe FHP produces a clear CVA drop and is already separable.
- Mild vs severe FHP is imperfect but directionally usable.

### 3.2 What is failing
- `lookingDown` samples in eye-level setups can produce a CVA drop similar to mild FHP.
- Under current rules, those samples are biased toward `forwardHead`.
- The current classifier treats FHP as the priority path and relies heavily on face-size shrink / forward-depth increase to confirm translation.
- In practice, eye-level downward gaze can still look "forward enough" in current features, so the classifier falls through to `forwardHead`.

### 3.3 Why this matters
- `PostureAnalyzer` recovers 50% of CVA drop only for `lookingDown`.
- If `lookingDown` is mislabeled as `forwardHead`, the score is harsher than intended.
- That creates false-positive FHP coaching even when the user's neck flexion is the dominant change.

## 4. Scope
This rule draft applies only when all of the following are true:
1. The runtime context is `eye_level`.
2. Yaw is within a usable range.
3. The system has valid baseline pitch and face-size information.

Outside that scope, the current classification path should remain unchanged.

## 5. Current Implementation Constraints
Relevant current behavior:
- `PostureClassifier` already uses:
  - `cvaDrop`
  - `pitch`
  - `faceSizeChange`
  - `forwardDepth`
  - `irisGazeOffset`
  - `yawDegrees`
- `PostureAnalyzer` already gives `lookingDown` partial CVA recovery.
- `PostureEngine` already uses `classification` for notification suppression and UX copy.

That means the next rule set should:
- reuse existing fields first
- avoid introducing heavy new model logic
- produce a discrete classification with simple confidence states

## 6. Candidate Signals To Use
The signals below are already available or derivable from current data.

### 6.1 Primary signals
- `pitchDrop = baselinePitch - currentPitch`
- `cvaDrop = baselineCVA - currentCVA`
- `faceSizeChange = (currentFaceSize - baselineFaceSize) / baselineFaceSize`
- `depthIncrease = currentForwardDepth - baselineForwardDepth`

### 6.2 Secondary signals
- `irisGazeDelta = currentIrisGazeOffset - baselineIrisGaze`
- `yawDegrees`
- `earsVisible`

### 6.3 Signal interpretation in eye-level context
- `forwardHead`
  - expected: clear `cvaDrop`
  - expected: translation evidence present
  - translation evidence means at least one of:
    - meaningful face-size shrink
    - meaningful forward-depth increase
  - pitch change may be small or moderate, but is not the dominant signal

- `lookingDown`
  - expected: `cvaDrop` exists
  - expected: pitch change is dominant
  - expected: translation evidence is weak or absent
  - optional support: downward iris gaze agrees with pitch

## 7. Proposed Rule Hierarchy
The order matters. This should be implemented as a narrow eye-level override in front of the current generic fallback path.

### Step 1. Quality gate
Return `unknown` and use existing behavior if any of these are true:
- `yawDegrees >= 20`
- baseline face size is missing
- baseline pitch is missing
- landmark quality is poor
- `earsVisible == false` and depth proxy is unavailable

Reason:
- this separation should not run on weak geometry.

### Step 2. Require meaningful posture deviation
If `cvaDrop <= 1.5`, return `normal`.

Reason:
- do not spend rule complexity on noise.

### Step 3. Check for confident forward translation first
If either of these is true, classify as `forwardHead`:
- strong face-size shrink
- strong forward-depth increase

Draft thresholds:
- `faceSizeChange <= -0.08`
- `depthIncrease >= 0.06`

Reason:
- these are the clearest signals that the head translated forward, not just tilted downward.

### Step 4. Add an eye-level looking-down override
If all of these are true, classify as `lookingDown`:
- `cvaDrop` is meaningful
- `pitchDrop` is meaningful
- translation evidence is weak

Draft thresholds:
- `cvaDrop >= 3`
- `pitchDrop >= 5`
- `faceSizeChange > -0.05`
- `depthIncrease < 0.04`

Optional strengthening:
- if `irisGazeDelta` also indicates downward gaze, increase confidence

Reason:
- this is the current blind spot: CVA worsens because the head tilted down, not because the neck translated forward.

### Step 5. Handle the ambiguous middle zone explicitly
If the sample does not satisfy Step 3 or Step 4:
- classify as `mixed` when pitch and translation are both moderately present
- otherwise keep current fallback behavior

Draft ambiguous examples:
- `pitchDrop >= 4` and `faceSizeChange <= -0.05`
- `pitchDrop >= 4` and `depthIncrease >= 0.04`

Reason:
- the current system jumps too quickly to `forwardHead`.
- `mixed` is safer than pretending the posture is pure FHP.

### Step 6. Final fallback
If the eye-level override cannot classify confidently:
- fall back to the current `PostureClassifier` logic
- do not invent a new score path

Reason:
- this preserves current desktop and non-eye-level behavior.

## 8. Proposed Confidence Policy
Classification should return both a label and a simple confidence bucket.

### High confidence `forwardHead`
Conditions:
- strong face shrink, or
- strong depth increase

Action:
- keep current forward-head score path

### High confidence `lookingDown`
Conditions:
- pitchDrop clearly above threshold
- weak translation evidence
- optionally supported by iris gaze

Action:
- apply current `lookingDown` CVA recovery path

### Medium confidence `mixed`
Conditions:
- moderate pitch signal and moderate translation signal both present

Action:
- use conservative scoring
- suppress aggressive FHP-specific messaging

### Low confidence / unknown
Conditions:
- high yaw
- missing baseline fields
- poor landmark quality
- conflicting features

Action:
- fall back to current generic behavior
- do not change desktop logic

## 9. Proposed Implementable Rule Stack
This is the intended stack in order.

1. Context gate:
   - apply only in `eye_level`
2. Quality gate:
   - reject if yaw or landmark quality is bad
3. Noise gate:
   - if `cvaDrop <= 1.5`, return `normal`
4. Strong translation:
   - if `faceSizeChange <= -0.08` or `depthIncrease >= 0.06`, return `forwardHead`
5. Strong pitch-dominant flexion:
   - if `cvaDrop >= 3` and `pitchDrop >= 5` and `faceSizeChange > -0.05` and `depthIncrease < 0.04`, return `lookingDown`
6. Ambiguous blended case:
   - if moderate pitch and moderate translation are both present, return `mixed`
7. Fallback:
   - use current classifier result

## 10. What Should Remain Unchanged
The following should remain unchanged in the first implementation:
- Desktop and non-eye-level contexts keep the current classification path.
- Severe FHP detection should keep its current aggressive behavior.
- Existing score thresholds and menu-bar hysteresis should stay unchanged.
- Existing `lookingDown` score recovery behavior in `PostureAnalyzer` should stay unchanged.
- Existing UX copy outside eye-level-specific corrections should stay unchanged.

This is important because the current desktop path is the non-regression baseline.

## 11. Explicit Non-Goals
This draft is not trying to do the following:
- redesign the entire posture taxonomy
- solve laptop-vs-desktop context inference
- introduce a learned classifier
- remove all false positives in one pass
- tune per-user thresholds automatically
- change severity thresholds or notification cadence
- handle extreme yaw, occlusion, or bad framing beyond existing fallback

## 12. Suggested Minimal Implementation Plan
### Phase 1. Log-only
- Add an eye-level-only debug classification result:
  - `eyeLevelForwardHead`
  - `eyeLevelLookingDown`
  - `eyeLevelMixed`
  - `eyeLevelFallback`
- Compare against current `classification` in logs.

### Phase 2. Classification-only switch
- Use the new eye-level rule stack only for `classification`.
- Keep scoring logic untouched except for the existing `lookingDown` recovery already present.

### Phase 3. Threshold tuning
- Tune only these thresholds first:
  - pitch-dominant threshold
  - weak-translation threshold
  - ambiguous mixed threshold

## 13. Validation Checklist
Success means:
- Good remains stable.
- Severe FHP remains `forwardHead`.
- obvious eye-level downward gaze stops collapsing into `forwardHead`.
- coaching copy says "lift your gaze" more often in the correct cases.
- desktop behavior remains unchanged.

Failure means:
- mild FHP starts getting relabeled as `lookingDown`
- desktop scores shift
- too many `mixed` labels appear in normal use

## 14. Decision Summary
The next change should not be a full scorer rewrite.

The practical change is:
- add an `eye_level`-specific override layer
- separate pitch-dominant neck flexion from translation-dominant forward head
- use `mixed` and fallback more deliberately instead of forcing borderline cases into `forwardHead`

This gives a low-risk path to better coaching behavior without destabilizing the desktop baseline.
