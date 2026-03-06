# Camera Selection Plan (Multi-Agent)

## Goal
- Do not ban Insta360.
- Avoid accidental defaulting to Insta360 for fresh DMG installs.
- Allow users to explicitly choose Insta360 in manual mode.

## Fixed Requirements
1. Default mode is `Auto (Recommended)`.
2. `Auto` should prefer macOS user/system preference when available.
3. `Auto` should avoid virtual-camera-first behavior when no explicit preference exists.
4. `Manual` mode must allow selecting any detected camera, including Insta360.
5. Persist manual selection and reuse it across launches.

## Shared Contract (Locked)
- New enum: `CameraSourceMode` with `auto`, `manual`.
- New value object: `CameraDeviceOption` (`id`, `displayName`, `modelID`, `isVirtual`).
- Storage keys:
  - `cameraSourceMode`
  - `manualCameraDeviceID`
- CameraManager API:
  - `static func discoverVideoDevices() -> [CameraDeviceOption]`
  - `func start(sourceMode: CameraSourceMode, manualDeviceID: String?) async throws`
  - `var activeDevice: CameraDeviceOption? { get }`

## Ownership Map
- Track A (Core Camera):
  - `TurtleneckCoach/Models/CameraSourceMode.swift`
  - `TurtleneckCoach/Core/CameraManager.swift`
- Track B (Engine + UI wiring):
  - `TurtleneckCoach/Core/PostureEngine.swift`
  - `TurtleneckCoach/Views/SettingsView.swift`
- Master-only integration checks:
  - `build.sh`, build/test commands, final regression check

## Quality Gates
1. Track gate
- Build passes for touched scope.
- No file ownership violation.
- Risk note included in worker handoff.

2. Integration gate
- `./build.sh` succeeds.
- Camera settings compile and render.
- Monitoring start still works with default `Auto`.

3. Regression gate
- Fresh state (`cameraSourceMode` unset): app does not hard-pin Insta360.
- Manual mode: selecting Insta360 is preserved and reused.
- If manual camera disappears, app falls back with clear error/auto path.

## Task Checklist
- [x] Add model types and storage keys.
- [x] Implement auto-selection policy with virtual-camera de-prioritization.
- [x] Implement manual camera selection path.
- [x] Expose camera options + current active camera in engine.
- [x] Add Settings UI for source mode + device picker.
- [x] Build and smoke test.
