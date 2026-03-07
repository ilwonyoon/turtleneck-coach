# TurtleNeckCoach Camera Position UX Spec
Date: 2026-03-06
Owner: PT_turtle experiment session

## 1. Problem Statement
The product currently needs to adapt posture scoring to camera geometry without making the UI heavier or more confusing.

The previous mental model, `desktop vs laptop`, is not the right primary UX abstraction. Users do not actually care what the device class is. What matters is where the camera sits relative to their eyes, because that changes how posture is interpreted.

At the same time, the current menu bar and sidebar surfaces are intentionally compact. That constraint should remain. The app should not flood those surfaces with technical context labels, calibration theory, or unstable internal posture distinctions.

The UX problem is therefore:
1. Make camera-height-aware scoring understandable enough to trust.
2. Keep the compact surfaces concise.
3. Put explanation only where users expect explanation: the popover control, calibration flow, and help copy.
4. Avoid exposing unstable internals, especially around `lookingDown` vs `forwardHead` while that logic is still being tuned.

## 2. UX Goals
1. Make the user-facing model simple: camera position relative to eyes.
2. Preserve current lightweight menu bar/sidebar interaction.
3. Give users a clear place to choose camera position directly in the popover.
4. Explain recalibration only when it is useful.
5. Avoid alarming or overexplaining during normal use.
6. Protect trust by not exposing unstable diagnostics as if they were final product behavior.

## 3. Terminology
Primary term:
- `Camera Position`

Primary values:
- `Above Eye Level`
- `Eye Level`
- `Below Eye Level`
- `Unknown`

Secondary term:
- `Device`

Secondary values:
- `Laptop`
- `External Monitor`
- `Unknown`

Support terms:
- `Distance`: `Near`, `Far`, `OK`
- `Framing`: `Good`, `Needs Adjustment`

Terms to avoid on user-facing compact surfaces:
- `verticalRelation`
- `contextConfidence`
- `lookingDown classifier`
- `forwardHead evidence`
- `eye-level narrow helper`

Rationale:
- `Camera Position` is understandable and directly tied to setup.
- `Device` is still useful in Settings and diagnostics, but should not be framed as the main reason scores behave differently.

## 4. Surface Model
### 4.1 Menu Bar And Sidebar
Menu bar and sidebar messaging must stay concise.

These surfaces should answer only:
1. Is monitoring on?
2. Is posture good / needs correction / bad?
3. Is there a short setup issue that blocks confidence?

They should not attempt to explain scoring theory.

The popover may include a compact manual `Camera Position` chooser as a control surface, as long as:
1. The live status copy stays short
2. The chooser uses brief labels only
3. Longer explanation stays in Settings/help

### 4.2 Popover
The popover is the main place for:
1. Viewing current `Camera Position`
2. Changing it directly
3. Seeing whether the current state is manual or auto

### 4.3 Settings
Settings is the secondary place for:
1. Viewing current `Camera Position`
2. Seeing supporting `Device` metadata
3. Understanding when recalibration is recommended

### 4.4 Calibration Flow
Calibration is the right moment to explain:
1. Why camera position matters
2. That calibration is stored against the current camera position
3. When setup changes may require recalibration

### 4.5 Help / Learn More
Help copy can carry the deeper explanation:
1. Why eye-level setups often score more stably
2. Why below-eye setups can confuse downward-looking posture with forward-head posture
3. Why the app may ask for recalibration after setup changes

## 5. Popover Surface Spec
### 5.1 Section Title
Use:
- `Camera Position`

Do not use:
- `Camera Context`
- `Vertical Relation`

### 5.2 Primary Control
Control label:
- `Camera Position`

Options:
- `Above Eye Level`
- `Eye Level`
- `Below Eye Level`
- `Auto`

Behavior:
- The three manual choices should come first in the popover
- `Auto` should be visually secondary
- Manual override persists until changed back
- Manual override does not need to expose confidence

Popover behavior:
- The user should be able to switch positions directly from the popover without opening Settings.
- Use a native dropdown/menu control in the popover, not large custom buttons.
- `Auto` should be available, but visually secondary to the three explicit positions.
- Changing the position while monitoring should trigger recalibration automatically.
- If monitoring is paused, changing the position should not auto-start monitoring; it should mark calibration as stale until the next calibration.

### 5.3 Compact Summary
Show one compact status line or chip near the control:
- `Above Eye Level`
- `Eye Level`
- `Below Eye Level`
- `Auto`

Do not show confidence percentages in the popover.

### 5.4 Supporting Metadata
The popover or Settings may show a secondary row:
- `Device: Laptop`
- `Device: External Monitor`

This row is informational only.
It must not appear above `Camera Position` in visual hierarchy.

### 5.5 Setup Quality Rows
The popover or Settings may show short health rows when available:
- `Distance: OK / Near / Far`
- `Framing: Good / Needs Adjustment`

These are setup quality indicators, not posture states.

## 6. Settings Surface Spec
Settings should mirror the popover choice, not own it.

Show:
- current `Camera Position`
- whether the current state is `Manual` or `Auto`
- supporting `Device` metadata
- recalibration guidance when relevant

Settings does not need a heavier duplicate control if the popover already provides the primary selector.

## 7. Calibration Messaging Spec
### 7.1 Pre-Calibration Copy
Short copy near the calibration CTA:
- `Sit naturally and look at your screen.`
- `We'll calibrate for your current camera position.`

Optional secondary copy:
- `Choose the camera position that matches your setup before calibrating.`

### 7.2 Completion Copy
On success:
- `Calibrated for Eye Level camera position.`
- `You can change this in the popover if needed.`

If height is unknown:
- `Calibration saved for your current setup.`
- `If scores feel off, change Camera Position in the popover.`

### 7.3 Recalibration Prompt Copy
When setup quality or camera position changes enough to matter:
- `Camera setup changed. Recalibration recommended.`

Do not say:
- `Classifier confidence dropped`
- `Vertical relation changed from below_eye to eye_level`

### 7.4 Calibration Help Copy
In expandable help or linked help:
- `Camera height affects how neck posture looks on camera.`
- `Eye-level setups are usually the most stable.`
- `Lower camera setups can make looking down resemble forward head posture.`

## 8. Concise Menu Bar Rules
The menu bar must stay short.

### 8.1 Allowed Message Types
1. Status
- `Monitoring`
- `Paused`
- `Camera Needed`

2. Setup issue
- `Adjust Camera`
- `Recalibrate`

3. Camera Position
- `Above Eye Level`
- `Eye Level`
- `Below Eye Level`
- `Auto`

4. Posture summary
- existing posture message system remains primary

### 8.2 Compact Camera-Position Labels
Do not show full explanatory phrases in the menu bar.
If camera position is shown at all, use a compact secondary label only.

Allowed examples:
- `Above Eye Level`
- `Eye Level`
- `Below Eye Level`

Disallowed examples:
- `Camera is below eye level so scores may over-detect forward head`
- `Looking down may collapse into forward head here`

### 8.3 Popover Choice Rule
The popover may include a clear camera-position choice control even on compact surfaces.

Requirements:
1. Keep the control visually compact
2. Put the three manual choices first
3. De-emphasize `Auto`
4. Avoid extra explanatory copy unless the selection is uncertain

### 8.4 Sidebar / Popover Rule
If the sidebar or popover already has a small status chip area, camera position may appear as a single concise chip.
Example:
- `Eye Level`

No long explanation text should be added there.

## 9. What Not To Expose Yet
Do not expose the following in product-facing UI yet:
1. `lookingDown` as a visible posture category
2. Any forward-head vs looking-down evidence scores
3. Confidence percentages anywhere in product-facing UI
4. `depth`, `iris`, or other raw feature terminology
5. Internal classifier disagreements
6. Experimental labels such as `eye-level helper` or `narrow classifier`

Reason:
- The `lookingDown` path is still behaviorally unstable in some setups.
- Surfacing it too early would turn internal debugging into user-facing product promises.
- Users need reliable explanations, not partial diagnostics.

## 10. Rollout Phases
### Phase 1: Quiet Foundations
- Add compact `Camera Position` selection directly in the popover
- Put manual choices first and de-emphasize `Auto`
- Add calibration copy that references current camera position
- Keep unstable internals hidden

### Phase 2: Soft Guidance
- Show compact `Eye Level` / `Above Eye Level` / `Below Eye Level` chip after calibration
- Add recalibration prompt when setup meaningfully changes
- Keep all long explanation in Settings/help only

### Phase 3: Better Explanation
- Add concise help entry explaining why camera position matters
- Add stronger setup guidance for below-eye users without cluttering live surfaces
- Still avoid exposing `lookingDown` internals directly

### Phase 4: Mature Adaptive UX
- Once the posture logic is stable, decide whether a user-facing downward-looking concept belongs anywhere
- Only expose it if it improves trust and actionability without confusing the main posture model

## 11. Copy Principles
1. Explain setup, not algorithms.
2. Prefer `Camera Position` over technical model names.
3. Keep live surfaces terse.
4. Put direct user choice in the popover before deeper explanation in Settings/help.
5. Do not expose unstable posture distinctions as if they are final.

## 12. Acceptance Criteria
1. Menu bar/sidebar remains as concise as today.
2. Users can change `Camera Position` directly in the popover without opening Settings.
3. Calibration copy explains why setup matters in one or two lines max.
4. Device type appears only as secondary information.
5. No user-facing surface exposes raw classifier internals or unstable `lookingDown` behavior yet.
