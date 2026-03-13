# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build the app (compiles Swift, creates .app bundle, code-signs with camera entitlement)
./build.sh

# Run
open TurtleneckCoach.app

# Start MediaPipe Python server
# Product rule: MediaPipe is required for shippable turtle-neck tracking quality.
source venv/bin/activate
python python_server/pose_server.py
```

Build uses direct `swiftc` (not xcodebuild). Target: `arm64-apple-macos14`. All 18 Swift source files are compiled in a single invocation. The Xcode project exists for IDE development but `build.sh` is the canonical build method.

## Distribution

Release packaging/notarization docs and scripts:

- Guide: [`docs/DISTRIBUTION.md`](/Users/ilwonyoon/Documents/Turtle_neck_detector/docs/DISTRIBUTION.md)
- Release build: `./scripts/build-release.sh [SIGNING_IDENTITY]`
- DMG packaging: `./scripts/create-dmg.sh ./TurtleneckCoach.app`
- Notarization: `./scripts/notarize.sh ./TurtleneckCoach-<version>.dmg [KEYCHAIN_PROFILE]`

Quick flow:

```bash
# 1) Build/sign app (ad-hoc by default, Developer ID if identity is provided)
./scripts/build-release.sh

# 2) Create DMG
./scripts/create-dmg.sh ./TurtleneckCoach.app

# 3) Notarize + staple (requires Apple credentials/keychain profile)
./scripts/notarize.sh ./TurtleneckCoach-1.0.0.dmg turtle-notary
```

Non-negotiable product constraint:

- MediaPipe is a must-have for turtle-neck tracking quality in shipped builds.
- Do not propose or implement Vision-only public releases unless the user explicitly changes that requirement.
- Release packaging must keep bundled MediaPipe assets working.

## Testing

Tests are standalone Swift scripts in the project root, compiled and run manually:

```bash
swiftc test_logic.swift -o test_logic -framework Vision -framework AVFoundation -framework AppKit -parse-as-library
./test_logic

# Camera/detection tests (require camera access)
swiftc test_camera.swift -o test_camera -framework AVFoundation -framework AppKit
./test_camera
```

No XCTest framework is integrated. Test files: `test_logic.swift`, `test_camera*.swift`, `test_face_landmarks.swift`, `test_3d_pose.swift`, `test_vision_file.swift`.

## Architecture

macOS menu bar app (LSUIElement, no Dock icon) that monitors posture via camera and provides real-time CVA (Craniovertebral Angle) scoring.

### Core Pipeline

```
CameraManager (AVCaptureSession, frame rotation)
    → VisionPoseDetector (batched 3D/2D/face detection)
    → PostureAnalyzer (CVA → severity → 0-100 score)
    → PostureEngine (orchestrator, @MainActor, publishes state)
    → SwiftUI Views (reactive via @Published)
    → NotificationService (macOS alerts on sustained bad posture)
```

### Detection Fallback Chain (priority order)

1. **3D body pose** (macOS 14+, `VNDetectHumanBodyPose3DRequest`) — most accurate, real Z-depth
2. **2D body pose** (`VNDetectHumanBodyPoseRequest`) — fallback when 3D unavailable
3. **Face landmarks** (`VNDetectFaceLandmarksRequest`) — robust when shoulders occluded
4. **MediaPipe server** (Python process via Unix socket `/tmp/pt_turtle.sock`) — required for shipped-quality turtle-neck tracking

All three Vision requests are batched in a single `handler.perform()` call.

Important:

- Vision fallback keeps the app from failing hard, but it is not an acceptable shipping substitute for MediaPipe.
- For this product, MediaPipe remains required in public release builds.

### Key Components

- **PostureEngine** (`Core/PostureEngine.swift`): Central orchestrator. Owns timer loop (3s interval), camera, detector, analyzer. All UI state flows through `@Published` properties.
- **VisionPoseDetector** (`Core/VisionPoseDetector.swift`): Runs Vision framework requests. Extracts CVA from 3D pose (`atan2(verticalDist, forwardDist)`), face-based estimation as fallback.
- **PostureAnalyzer** (`Core/PostureAnalyzer.swift`): CVA thresholds based on clinical literature. Piecewise-linear score mapping. Severity enum: good/mild/moderate/severe.
- **CalibrationManager** (`Core/CalibrationManager.swift`): 20-sample calibration on every app start. Stores baseline CVA ratio in UserDefaults.
- **MediaPipeClient** (`Core/MediaPipeClient.swift`): IPC with Python server via Unix Domain Socket. Required for shipped tracking quality; fallback-only operation is a safety net, not an acceptable release target.

### Python Components

`python_server/pose_server.py`: MediaPipe Tasks API server. Listens on Unix socket. Provides 478-landmark face mesh and body pose, and must remain part of the shipped release path.

`src/`: Original Python prototype (pose_detector.py, detector.py, calibration.py). Used for comparison testing (compare_cva.py).

## Key Conventions

- **Immutability**: All models are `struct`. State updates create new instances, never mutate. This is enforced project-wide.
- **Thread safety**: PostureEngine is `@MainActor`. CameraManager uses background queue. Frame storage protected by `NSLock`.
- **Calibration on every start**: App forces recalibration each launch to match current session conditions.
- **CVA thresholds (clinical)**: Good >=52°, Mild 42-52°, Moderate 32-42°, Severe <32°.
- **UI throttling**: Frame updates at 15fps, analysis at ~3fps (monitoring) / 5fps (calibration).
- **Debug log**: CVA signal diagnostics written to `/tmp/turtle_cvadebug.log`.

## Frameworks (all Apple built-in, no SPM dependencies)

SwiftUI, Vision, AVFoundation, UserNotifications, AppKit, Network

## Design System

All visual constants live in `TurtleneckCoach/DesignSystem/DesignTokens.swift` under the `DS` namespace.

- **Primitive tokens**: `DS.Font`, `DS.Space`, `DS.Radius`, `DS.Palette` — raw values
- **Semantic tokens**: `DS.Severity`, `DS.Surface`, `DS.Label`, `DS.Size` — intent-based
- **Lint**: `./scripts/lint-design-tokens.sh` — catches hardcoded fonts, colors, radii, materials in view files
- **One-offs**: Mark with `// DS: one-off` comment to suppress lint warnings
- **Rule**: New views MUST use `DS.*` tokens. No raw font sizes, colors, or spacing in view files.

## Token Economy: Codex-First Delegation Strategy

**Codex's role is ORCHESTRATOR. Codex does the heavy lifting.** This saves Codex tokens dramatically by offloading expensive read/write/analysis work to Codex.

### When to Delegate to Codex (ALWAYS for these)

| Task Type | Codex Command | Why Codex |
|-----------|---------------|-----------|
| **Code review** | `codex-collab review` | Reads all files, no Codex tokens spent |
| **Multi-file refactoring** | `codex-collab run "refactor X across Y"` | Edits many files without Codex context |
| **New feature implementation** | `codex-collab run "implement X"` | Full implementation without Codex reading/writing |
| **Bug investigation** | `codex-collab run "find why X happens" -s read-only` | Deep codebase search on Codex's dime |
| **Test writing** | `codex-collab run "write tests for X"` | Reads source + writes tests, all on Codex |
| **Documentation** | `codex-collab run "document X"` | Reads code and generates docs via Codex |
| **Architecture analysis** | `codex-collab run "analyze architecture of X" -s read-only` | Deep multi-file analysis on Codex |
| **Performance audit** | `codex-collab run "find performance issues" -s read-only` | Full codebase scan on Codex |

### When Codex Should Act Directly (token-cheap)

- Quick single-file reads (< 100 lines)
- User communication and status updates
- Task orchestration and planning decisions
- Running build/test commands (`./build.sh`)
- Small single-line edits when faster than a Codex roundtrip

### Codex Concurrency Limits

**Maximum 3 simultaneous Codex threads.** More than 3 causes threads to be killed (exit 144). Account for threads from OTHER projects sharing the same Codex app-server.

- Launch up to 3 parallel tasks
- When one completes, start the next (pipeline approach)
- Check `codex-collab jobs` to see total active threads across all projects
- Use `--timeout 600` for complex research tasks (default may be too short)

### Codex Command Reference

All `codex-collab` Bash calls MUST use `dangerouslyDisableSandbox=true`. Use `run_in_background=true` for `run` and `review` commands (they take minutes).

```bash
# Code review (PR-style diff review)
codex-collab review -d /Users/ilwonyoon/Documents/Turtle_neck_detector --content-only

# Code review (uncommitted changes only)
codex-collab review --mode uncommitted -d /Users/ilwonyoon/Documents/Turtle_neck_detector --content-only

# Read-only research / investigation
codex-collab run "describe the detection fallback chain in VisionPoseDetector" -s read-only --content-only

# Implementation task (Codex reads, edits, and writes files)
codex-collab run "add escalating notification severity to NotificationService.swift" --content-only

# Resume a previous thread for follow-up work
codex-collab run --resume <id> "now add tests for what you just implemented" --content-only

# Check progress on a running task
codex-collab progress <id>
```

### Workflow Pattern: Codex Orchestrates, Codex Executes

1. **User requests feature** → Codex plans the approach (cheap: text only)
2. **Implementation** → Codex delegates to Codex via `codex-collab run` (background)
3. **While Codex works** → Codex can handle other user questions or launch parallel Codex tasks
4. **Codex completes** → Codex reviews output summary, runs `./build.sh` to verify
5. **Issues found** → Codex resumes Codex thread: `codex-collab run --resume <id> "fix the build error: ..."`
6. **Done** → Codex reports to user

### Parallel Codex Tasks

Launch multiple independent Codex tasks simultaneously to maximize throughput:

```bash
# Task 1: Implement feature (background)
codex-collab run "implement BreakManager.swift with 25-min sitting detection" --content-only

# Task 2: Write tests (background, separate thread)
codex-collab run "write detection accuracy tests using saved reference frames" --content-only

# Task 3: Review existing code (background, read-only)
codex-collab review --mode uncommitted --content-only
```

### Token Savings Estimate

| Action | Codex-only cost | With Codex delegation |
|--------|------------------|-----------------------|
| Review 3000-line codebase | ~15K tokens (read all) | ~200 tokens (launch command) |
| Implement new feature | ~8K tokens (read+write) | ~200 tokens (launch + verify build) |
| Investigate bug across files | ~10K tokens (multi-read) | ~200 tokens (launch read-only) |
| Refactor 5 files | ~12K tokens (read+edit all) | ~200 tokens (launch + review result) |
