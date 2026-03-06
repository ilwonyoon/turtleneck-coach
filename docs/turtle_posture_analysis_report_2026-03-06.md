# TurtleNeckCoach Posture Detection Analysis Report
Date: 2026-03-06

## 1) Scope
This report summarizes observed posture-detection behavior from debug sessions collected on laptop setup, including:
- Good vs Forward Head Posture (FHP) capture cycles
- Distance changes (D0 to D2; D3 excluded because face framing became invalid)
- Score behavior and geometry signals (`faceY`, `faceH/faceSize`, `cvaDrop`)

Data sources:
- `/tmp/turtle_cvadebug.log`
- `/tmp/turtle_manual_snapshots/*`

## 2) Dataset Snapshot
Captured snapshot folders (6 images each) include:
- `20260306_101445_GOOD_POSTURE`
- `20260306_101452_FORWARD_HEAD`
- `20260306_101658_GOOD_POSTURE`
- `20260306_101706_FORWARD_HEAD`
- `20260306_102813_GOOD_POSTURE`
- `20260306_102820_FORWARD_HEAD`
- `20260306_102830_FORWARD_HEAD`
- `20260306_102849_GOOD_POSTURE`
- `20260306_102857_FORWARD_HEAD`
- `20260306_102904_FORWARD_HEAD`
- `20260306_102927_GOOD_POSTURE`
- `20260306_102937_FORWARD_HEAD`
- `20260306_102944_FORWARD_HEAD`

Total snapshots: 78

## 3) Key Quantitative Findings
### 3.1 Good vs FHP separation (laptop setup)
Aggregate across debug sessions:
- **GOOD_POSTURE**
  - Score: min/med/max = **94 / 98 / 98** (avg 97.714)
  - rawCVA: min/med/max = **62 / 65 / 65** (avg 64.786)
  - faceY median = **0.480**
  - faceH(faceSize) median = **0.368**
- **FORWARD_HEAD**
  - Score: min/med/max = **24 / 83.5 / 98** (avg 74.667)
  - rawCVA: min/med/max = **26 / 56.85 / 65** (avg 52.305)
  - faceY median = **0.431**
  - faceH(faceSize) median = **0.459**

Interpretation:
- FHP generally shows **lower faceY** (face appears higher in frame) and **larger faceSize**.
- Score drop is clear in severe FHP, but mild FHP can overlap with good range.

### 3.2 Signal coupling
From paired Forward samples:
- corr(faceSize, score) = **-0.739**
- corr(cvaDrop, score) = **-0.943**

Interpretation:
- Score is influenced by geometry/size changes, but strongest coupling is with `cvaDrop`.

### 3.3 Distance/tilt-back behavior (D0 to D2)
Observed trend from recent distance blocks:
- Good posture remains mostly stable (typically 96–98).
- FHP detection still works, but **early response can become slower/softer** as position changes.
- In several cycles, score stayed high for first few frames before dropping later.

Practical interpretation:
- User-observed “score baseline feels elevated on laptop position changes” is consistent with logs.
- The main issue is not severe-FHP detectability (that still works), but **mild-FHP sensitivity consistency** under camera geometry shifts.

## 4) Laptop vs External Monitor Framing Difference
Current hard data is laptop-only. External monitor webcam comparison data has not yet been collected in the same protocol.

What can already be inferred from current sessions:
- Camera relative pose (higher/lower perspective) likely changes face framing features (`faceY`, `faceSize`) for the same real posture.
- If model thresholds are mostly global, this causes sensitivity drift across device/camera setups.

To make laptop-vs-monitor conclusions definitive, collect one mirrored monitor dataset with same sequence:
- Calibration → Good 5s → Mild FHP 5s → Severe FHP 5s (repeat 2x)

## 5) Why mild FHP is unstable compared to severe FHP
- Severe FHP creates large, clear deltas (`cvaDrop` and/or face geometry), so it is consistently detected.
- Mild FHP produces smaller deltas that are closer to noise from camera position, distance, and natural head motion.
- Result: mild FHP sometimes remains in good/mild boundary depending on setup.

## 6) Recommended Detection Strategy Updates
### 6.1 Use relative-to-baseline normalization (per setup)
- Keep a per-session baseline from Good capture.
- Classify from normalized deltas, not only absolute CVA score.

### 6.2 Add framing-aware compensation
- Use `faceSize` (distance proxy) and optional `faceY` context to adjust sensitivity.
- If framing shifts beyond tolerance, request short recalibration.

### 6.3 Use hysteresis for stable UX
- Different enter/exit thresholds for mild/moderate/severe.
- Avoid rapid oscillation near decision boundaries.

### 6.4 Explicit “framing quality gate”
- If face too close/far/off-center, freeze posture state and show “reposition” guidance.
- Prevent false confidence from poor framing.

## 7) Immediate Next Steps
1. Implement session report auto-generator from `turtle_cvadebug.log` + snapshot folders.
2. Add normalized mild-FHP rule set with hysteresis.
3. Add framing quality gate + recalibration trigger.
4. Collect mirrored external monitor dataset and compare against this baseline.

## 8) Bottom Line
- Current pipeline is already strong for severe FHP.
- Main gap is mild-FHP consistency across laptop camera geometry changes (distance/angle/framing).
- This is solvable with baseline normalization + framing compensation + hysteresis.
