# Minimal Additional Data Plan
Date: 2026-03-06
Owner: Track 3

## 1. Decision
The current bottleneck is no longer "collect more generic forward-head / down-looking data."

The latest experiments already established:
- severe forward head is detectable
- mild forward head instability is strongly coupled to camera geometry
- laptop-vs-monitor context drift exists

So the next bottleneck is redesign, not more broad data gathering.

Only a very small post-redesign dataset is still worth collecting:
- validate `eye_level forwardHead` vs `lookingDown` separation
- protect the existing desktop-monitor path from regression

## 2. Minimum Dataset To Collect After The Design Change
Collect only two validation packs.

### Pack A: Eye-Level Separation Pack
Purpose:
- verify that eye-level forward head is classified as `forwardHead`
- verify that neck-flexion/downward gaze is classified as `lookingDown`

Environment:
- one stable camera setup only
- prefer the setup that will be used for first redesign validation
- if redesign is laptop-first, use laptop only for this pack

Labels:
- `GOOD_EYE_LEVEL`
- `FHP_EYE_LEVEL_MILD`
- `FHP_EYE_LEVEL_SEVERE`
- `LOOKING_DOWN_NECK_FLEXION`
- `LOOKING_DOWN_EYES_ONLY`

Required captures:
- calibration: 1
- each label: 2 clips
- clip length: 5 seconds

Total clips:
- 10 labeled clips + 1 calibration

### Pack B: Desktop Regression Safety Pack
Purpose:
- confirm that the existing desktop/monitor path did not materially change

Environment:
- one known-good external monitor / desktop webcam setup
- same camera and placement previously considered stable

Labels:
- `DESKTOP_GOOD`
- `DESKTOP_FHP_MILD`
- `DESKTOP_FHP_SEVERE`

Required captures:
- calibration: 1
- each label: 2 clips
- clip length: 5 seconds

Total clips:
- 6 labeled clips + 1 calibration

## 3. Exact Capture Protocol
Apply this protocol exactly to both packs.

1. Start a fresh app session.
2. Confirm the target camera context is fixed for the entire pack.
3. Run calibration once.
4. Wait 1 second in a stable pose.
5. Start the labeled 5-second capture.
6. Hold the pose for the full 5 seconds without changing distance.
7. Rest 2 to 3 seconds.
8. Repeat the same label once more.
9. Move to the next label.

Per-label pose intent:
- `GOOD_EYE_LEVEL`: upright, neutral neck, eyes at screen level
- `FHP_EYE_LEVEL_MILD`: head translated forward, chin mostly level, avoid looking downward
- `FHP_EYE_LEVEL_SEVERE`: clearly forward head, still keep gaze near eye level
- `LOOKING_DOWN_NECK_FLEXION`: neck flexion downward toward screen/desk, not strong forward translation
- `LOOKING_DOWN_EYES_ONLY`: eyes look downward with minimal neck movement
- `DESKTOP_GOOD`: current known-good desktop posture
- `DESKTOP_FHP_MILD`: mild forward head on desktop setup
- `DESKTOP_FHP_SEVERE`: severe forward head on desktop setup

Artifacts to keep:
- `/tmp/turtle_cvadebug.log`
- debug capture folders for each labeled clip
- note of camera type used for the pack: `laptop` or `desktop`

## 4. Acceptance Criteria
### A. Eye-Level Separation
The redesign is good enough to proceed if all are true:

1. `FHP_EYE_LEVEL_MILD` is classified primarily as `forwardHead`, not `lookingDown`.
2. `FHP_EYE_LEVEL_SEVERE` is classified as `forwardHead` for both clips.
3. `LOOKING_DOWN_NECK_FLEXION` is classified primarily as `lookingDown`, not `forwardHead`.
4. `LOOKING_DOWN_EYES_ONLY` does not trigger severe forward-head scoring.
5. `GOOD_EYE_LEVEL` remains in the good range with no repeated false correction state.

### B. Desktop Regression Safety
The redesign is safe enough to continue if all are true:

1. `DESKTOP_GOOD` score remains effectively unchanged versus pre-redesign behavior.
2. `DESKTOP_FHP_SEVERE` still produces a clear score drop.
3. `DESKTOP_FHP_MILD` does not become harder to detect than before.
4. No new repeated flicker between good and correction on desktop good posture.

Recommended numeric guardrails:
- desktop good average score drift: within `+/- 2`
- desktop severe FHP: no missed clip
- eye-level mild FHP: both clips must separate from good by a visible score gap

## 5. Data That Is Not Worth Collecting Right Now
Do not spend time collecting the following before the redesign lands:

- more generic `Good` vs generic `FHP` repeats
- more severe FHP examples
- more laptop distance ladders like `D0/D1/D2`
- manual monitor-tilt sweeps
- large mixed-condition datasets across many camera positions
- more broad "looking down" clips without explicit eye-level control

Reason:
- these add volume, but do not answer the current design-risk question
- the next unknown is not "do we have enough posture examples?"
- the next unknown is "after redesign, can we separate eye-level forward head from looking down without breaking desktop behavior?"

## 6. Practical Recommendation
Stop general data collection now.

Implement the redesign first, then collect only:
- Pack A for classification separation
- Pack B for regression safety

That is the minimum dataset still worth paying attention to.
