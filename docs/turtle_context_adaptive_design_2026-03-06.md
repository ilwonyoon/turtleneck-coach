# TurtleNeckCoach Context-Adaptive Scoring Design
Date: 2026-03-06
Owner: PT_turtle experiment session

## 1. Purpose
This document consolidates two things into one design baseline:
1. What the current logs and capture sessions actually show
2. How the scoring system should adapt without regressing the monitor path

The central conclusion has changed. The primary context model should not be `desktop vs laptop`. It should be the camera's vertical relation to the user's eyes:
- `above_eye`
- `eye_level`
- `below_eye`

Device type remains useful, but only as secondary metadata and a fallback hint.

## 2. Evidence Summary From Current Sessions
Data sources:
- `/tmp/turtle_cvadebug.log`
- `/tmp/turtle_manual_snapshots/*`

Session characteristics:
- Most collected data came from laptop-camera setups
- Distance variation was collected across D0, D1, D2
- Good, mild forward head posture, and severe forward head posture were captured repeatedly
- Additional observation was made after introducing context UI and log-only inference

Measured patterns from the current set:
- Good posture remains relatively stable in score and raw CVA under the same camera geometry
- Severe forward head posture is usually separable already
- Mild forward head posture is the unstable zone and is sensitive to camera geometry
- As the laptop screen moves farther back, score drop often becomes delayed or compressed rather than fully disappearing

New experimental conclusion:
- An `eye_level` stand setup can separate Good vs forward head to some extent
- A `lookingDown` posture currently tends to collapse into `forwardHead`
- This means the current feature set is not cleanly separating neck translation from gaze/downward head orientation

Practical implication:
- The main problem is not "can the system detect extreme forward head posture?"
- The main problem is "can the system separate mild forward head posture from viewpoint-induced changes and from looking down?"

## 3. Why Device Type Alone Was The Wrong Abstraction
Using `desktop` vs `laptop` as the primary context was appealing because it maps to a visible hardware difference, but it is not the variable that directly distorts the posture signal.

Why it breaks down:
1. A laptop on a stand can behave like a monitor at eye level.
2. A monitor with a low webcam or unusual mount can behave like a below-eye camera.
3. The same laptop shifts geometry materially when the display tilts back or the user changes seating distance.
4. The score instability we observed tracks camera viewpoint geometry more directly than device class.

What the model actually needs to know:
1. Is the camera above the user's eyes, roughly level with them, or below them?
2. Is that geometry stable enough that a previous calibration still applies?
3. Is the current frame pattern more consistent with forward head translation or simply downward viewing?

Therefore:
- `deviceType` should be treated as metadata, not as the primary scoring context
- The primary context should be `verticalRelation`
- Distance/tilt/framing remain secondary modifiers beneath that context

## 4. Product Goals
1. The system infers the camera's vertical relation as `above_eye`, `eye_level`, or `below_eye`.
2. Calibration and scoring use a relation-specific baseline rather than a device-specific baseline.
3. Device type (`laptop`, `external_monitor`, `unknown`) is stored as supporting metadata only.
4. Distance, tilt, and framing quality are handled as secondary modifiers, not as the top-level context.
5. Existing monitor behavior must not regress while this model is introduced.

## 5. Design Principles
1. Non-regression on the current good monitor path remains the first constraint.
2. If inference confidence is low, the system must fall back to the current scoring path.
3. The system should adapt to geometry, not overfit to hardware labels.
4. Log-only validation should precede scoring changes.
5. Runtime overhead must stay bounded; context adaptation cannot introduce UI or camera freezes.

## 6. Primary Context Model
### 6.1 Runtime State
Primary runtime fields:
- `verticalRelation`: `above_eye | eye_level | below_eye | unknown`
- `verticalRelationConfidence`: `0.0 ... 1.0`
- `verticalRelationSource`: `auto | manual`

Secondary metadata:
- `deviceType`: `laptop | external_monitor | unknown`
- `deviceTypeConfidence`: `0.0 ... 1.0`
- `distanceState`: `neutral | too_near | too_far`
- `tiltState`: `neutral | tilt_back | tilt_forward | unknown`
- `framingQuality`: `good | degraded | invalid`

Interpretation:
- `verticalRelation` drives baseline selection
- `deviceType` informs UX, analytics, and fallback hints
- `distanceState`, `tiltState`, and `framingQuality` affect whether scoring should be trusted, softened, or paused

### 6.2 Why Vertical Relation Is The Primary Signal
The scoring problem is fundamentally viewpoint-sensitive:
- A camera above eye level changes facial and neck geometry differently from a camera below eye level
- The same posture can project differently depending on camera position
- Looking down can mimic some forward-head signals even without equivalent neck translation

A vertical-relation model is closer to the distortion source than a device-type model.

## 7. Calibration And Scoring Architecture
### 7.1 Calibration Profiles
Store calibration by vertical relation, not by device type.

Profile units:
- `aboveEyeProfile`
- `eyeLevelProfile`
- `belowEyeProfile`

Each profile stores:
- baseline CVA
- baseline face size
- baseline face vertical position
- short-window stability statistics
- framing quality markers
- last updated timestamp
- optional supporting metadata: observed `deviceType`

### 7.2 Scoring Pipeline
1. Evaluate framing quality
2. Infer `verticalRelation` and confidence
3. Load the matching relation profile if confidence is sufficient
4. Compute relative change against that profile
5. Detect disagreement between viewpoint shift and posture shift
6. Apply severity logic and hysteresis
7. Publish UI state only when outputs materially change

Fallback rules:
- `unknown` or low-confidence relation uses the current legacy scorer
- invalid framing pauses posture conclusions instead of forcing unstable scores

### 7.3 Relation-Aware Interpretation
Expected behavior by relation:
- `above_eye`: downward gaze can more easily resemble forward collapse; require stronger evidence of neck translation
- `eye_level`: Good vs forward head can separate somewhat already and should be the cleanest baseline for future tuning
- `below_eye`: looking-down patterns are especially likely to collapse into `forwardHead` and require additional guarding

### 7.4 Looking-Down Guard
The current experiment indicates a structural failure mode: `lookingDown` often collapses into `forwardHead`.

Design implication:
- The system should not treat all head-angle change as forward-head evidence
- It needs a guard layer that distinguishes forward translation from downward viewing when possible

Initial rule direction:
- If head orientation changes in a way consistent with downward viewing but forward-translation evidence is weak or inconsistent, soften or withhold forward-head escalation
- If both downward orientation and forward translation rise together, allow normal posture escalation

This should start as a conservative guard, not a fully separate classifier.

Detailed first-pass rule draft lives in:
- [eye_level_forward_vs_looking_down_rules_2026-03-06.md](/Users/ilwonyoon/Documents/PT_turtle/docs/eye_level_forward_vs_looking_down_rules_2026-03-06.md)

## 8. Inference Strategy
### 8.1 Inputs
Candidate inputs for inference:
- face vertical position over a short window
- face size over a short window
- baseline-relative landmark geometry
- head pitch/yaw trends
- framing stability
- optional device metadata from camera source and known setup history

### 8.2 Decision Policy
1. High-confidence relation inference applies automatically.
2. Low-confidence inference falls back to `unknown` and preserves legacy behavior.
3. User override can set `above_eye`, `eye_level`, or `below_eye` manually.
4. Device type can be shown in the UI as supporting context, but should not override the primary relation unless the user explicitly chooses it.

### 8.3 Secondary State Handling
- `distanceState` and `tiltState` do not change the primary relation by themselves
- They modify trust in the current calibration and can trigger recalibration guidance
- `framingQuality=invalid` suppresses scoring updates entirely

## 9. Performance And Regression Guardrails
This design must preserve the existing performance framing. Context adaptation is only acceptable if it does not worsen runtime stability.

Guardrails:
1. Vertical-relation inference runs in log-only mode first.
2. Legacy scoring remains the fallback for low-confidence or invalid-framing cases.
3. UI updates must be gated to material state changes only.
4. No new high-frequency logging or main-thread work should be added without profiling.
5. Monitor/stand setups that already work must remain within a tight score-drift envelope.

Runtime risks already seen in adjacent investigation:
- Main-thread analysis work can freeze preview responsiveness
- Repeated observed-object invalidation can amplify SwiftUI redraw cost
- Extra context logic is acceptable only if it is computationally cheap and publish-throttled

## 10. User Scenarios
### Scenario A: External Monitor With Camera Above Eye Level
- Flow: user calibrates once on a typical top-mounted webcam
- System: infers `above_eye`, stores an `aboveEyeProfile`
- Expected result: current good monitor behavior remains stable, with no forced change if confidence is weak

### Scenario B: Laptop On Stand At Eye Level
- Flow: user places laptop so the camera is roughly eye level and calibrates
- System: infers `eye_level`, stores an `eyeLevelProfile`
- Expected result: Good vs forward head should separate better than in the below-eye laptop case

### Scenario C: Laptop On Desk Below Eye Level
- Flow: user works directly on a laptop without a stand
- System: infers `below_eye`, stores a `belowEyeProfile`
- Expected result: scoring becomes more conservative around downward-looking states, reducing false forward-head escalation

### Scenario D: User Looks Down Frequently Without Strong Neck Translation
- Flow: user reads or types while maintaining mostly acceptable neck position
- System: detects a pattern more consistent with downward viewing than true forward translation
- Expected result: avoid collapsing immediately into `forwardHead` when evidence is insufficient

### Scenario E: User Alternates Between Monitor And Laptop Stand
- Flow: morning on an external monitor, afternoon on a raised laptop
- System: relation may remain the same (`above_eye` or `eye_level`) even though device type changes
- Expected result: calibration reuse is possible when geometry matches, which is exactly why device type should not be primary

### Scenario F: User Changes Tilt Or Distance Mid-Session
- Flow: laptop screen tilts back, or the user moves farther away
- System: preserves the same primary relation if camera position relative to eyes is unchanged, but marks distance/tilt as degraded context
- Expected result: either soften scoring confidence or request recalibration instead of pretending the top-level context changed

### Scenario G: Ambiguous Or Poor Framing
- Flow: face is partly cropped, too small, or unstable in frame
- System: relation confidence drops and framing quality degrades
- Expected result: fall back to legacy scoring or suppress updates rather than produce noisy adaptive behavior

## 11. Validation Plan
### 11.1 Core Questions
1. Does vertical relation explain score variation better than device type?
2. Does `eye_level` improve Good vs forward-head separation compared with `below_eye`?
3. Can we reduce `lookingDown -> forwardHead` collapse without harming true forward-head recall?
4. Can we do this without regressing existing monitor setups?

### 11.2 Required Datasets
Longer-term desired coverage:
- `above_eye`: Good / lookingDown / mild forward head / severe forward head
- `eye_level`: Good / lookingDown / mild forward head / severe forward head
- `below_eye`: Good / lookingDown / mild forward head / severe forward head

Supporting metadata to retain:
- device type
- distance bucket
- tilt notes if known
- framing quality

Immediate post-redesign minimum:
- do not collect the full matrix first
- collect only the smallest validation packs needed to answer the next risk:
  - `eye_level` separation pack
  - desktop regression pack

Detailed minimal collection plan lives in:
- [minimal_additional_data_plan_2026-03-06.md](/Users/ilwonyoon/Documents/PT_turtle/docs/minimal_additional_data_plan_2026-03-06.md)

### 11.3 Success Criteria
Initial acceptance targets:
- Existing good monitor setups stay within a score drift envelope of `<= 2` average points under legacy-equivalent conditions
- `eye_level` shows measurable separation between Good and forward head
- `lookingDown` false escalation rate drops meaningfully, especially in `below_eye`
- Severe forward-head recall is not degraded
- State flicker does not increase
- Runtime responsiveness does not worsen

## 12. Rollout Plan
### Phase 1: Log-Only Vertical Relation Inference
- infer `verticalRelation`, `deviceType`, and secondary states
- do not change scoring yet
- log relation confidence and disagreement cases such as `lookingDown` vs `forwardHead`

### Phase 2: Relation-Specific Calibration Profiles
- keep legacy scoring as the user-visible path
- store and validate relation-specific baselines in parallel
- compare legacy scores against relation-aware offline analysis

### Phase 3: Conservative Adaptive Scoring
- enable relation-aware scoring only for high-confidence cases
- keep legacy fallback for `unknown`, degraded framing, or unstable geometry
- activate the looking-down guard conservatively first

### Phase 4: Recalibration And UX Refinement
- add lightweight user guidance when tilt/distance changes make calibration stale
- expose manual override for `above_eye`, `eye_level`, `below_eye`
- keep device type visible only as supporting information

## 13. UX Implications
The UX should reflect the new abstraction directly.

Recommended presentation:
1. Primary label: `Camera Position Relation`
2. Values: `Above Eye`, `Eye Level`, `Below Eye`, `Unknown`
3. Secondary metadata: `Device: Laptop` or `Device: External Monitor`
4. Support states: `Distance`, `Tilt`, `Framing Quality`

UX rule:
- The primary label explains why scoring behaves differently
- Device type is informative, but not the thing the user is calibrating against

Implementation note:
- current shipped UI still uses `Desktop/Laptop` language in several places
- that terminology should be treated as transitional until the vertical-relation UX is implemented

## 14. Summary
- The observed instability is better explained by camera geometry than by hardware category.
- `desktop vs laptop` is too coarse to be the primary adaptive-scoring abstraction.
- The primary context should be `above_eye`, `eye_level`, `below_eye`.
- Device type remains useful as metadata, analytics, and a fallback hint.
- The most important unresolved posture failure mode is that `lookingDown` currently collapses into `forwardHead`, especially outside eye-level geometry.
- Rollout should remain conservative, log-first, and regression-protected.

## 15. Open Questions
1. Which feature combination best separates `lookingDown` from true forward translation at `below_eye`?
2. How stable is `verticalRelation` inference across real users without explicit setup instructions?
3. When relation confidence is low, should the product surface manual override immediately or stay silent and fall back?
4. How much calibration can be reused across different devices when the inferred vertical relation is the same?
