# MediaPipe Self-Contained Execution Plan

Date: 2026-03-06
Scope: public macOS DMG release
Out of scope: Intel support, Apple Developer account setup, notarization credential setup
Current release policy: Apple Silicon (`arm64`) / macOS 14.0+

## Goal

Ship a DMG that can run the MediaPipe posture path on a clean Apple Silicon Mac without depending on:
- repo-relative paths
- a user-installed Python runtime
- a developer-created local virtualenv
- pre-existing helper files under `~/.pt_turtle`

If the self-contained MediaPipe path is unavailable, the app must fail predictably and fall back to Vision without hanging or misleading the user.

## Current Risk Summary

Current runtime risks are concentrated in [MediaPipeClient.swift](/Users/ilwonyoon/Documents/PT_turtle/TurtleneckCoach/Core/MediaPipeClient.swift):

1. Script discovery currently checks multiple dev-oriented locations.
- `~/.pt_turtle/server/pose_server.py`
- repo-relative paths
- bundled resource path
- current working directory

2. Python runtime discovery is not fully self-contained.
- prefers `.venv/bin/python3` next to the server
- otherwise falls back to `/usr/bin/env python3`

3. Clean-machine DMG readiness is therefore not guaranteed.
- clean Macs cannot be assumed to have a suitable `python3`
- bundled resources may exist, but execution of the helper still depends on runtime packaging strategy

## Recommended Target Architecture

### Public release target

For public DMG release, the app should use only these runtime assumptions:
1. `pose_server.py` and required model files exist in `Contents/Resources/python_server/`
2. the app launches a bundled Python runtime from inside the app bundle
3. all required Python packages for the helper are bundled inside the app resources
4. if helper startup fails, the app falls back to Vision cleanly and surfaces a minimal release-safe state

### Non-goals

1. Intel support in this phase
2. Mac App Store compatibility in this phase
3. removing Vision fallback

## Packaging Options

### Option A: Bundle a dedicated Python runtime inside the app

Structure example:
- `TurtleneckCoach.app/Contents/Resources/python_runtime/bin/python3`
- `TurtleneckCoach.app/Contents/Resources/python_server/pose_server.py`
- `TurtleneckCoach.app/Contents/Resources/python_server/models/...`
- `TurtleneckCoach.app/Contents/Resources/python_packages/...`

Pros:
- predictable on clean machines
- no dependency on system Python
- strongest public DMG story

Cons:
- app size increases
- hardened runtime / signing validation must be checked
- packaging script complexity increases

### Option B: Bundle a venv-like layout directly under `python_server/.venv`

Pros:
- closest to current code
- lower refactor cost

Cons:
- still needs careful relocation validation
- less explicit than a dedicated runtime layout
- easier to accidentally ship dev-specific paths

### Recommendation

Choose Option A.
It is clearer, more deterministic, and easier to document as the official DMG runtime model.

Important policy constraint:
- do not ship a public DMG with a runtime vendored from Xcode's `Python3.framework`
- use a separately sourced distributable Python runtime for the final release build

## Implementation Phases

### Phase 1: Freeze the public runtime contract

Files likely touched:
- `TurtleneckCoach/Core/MediaPipeClient.swift`
- `scripts/build-release.sh`
- release docs

Tasks:
1. Make bundled runtime/resource paths the primary release path.
2. Keep dev-only fallback paths behind explicit development behavior.
3. Document the exact expected bundle layout.

Exit criteria:
- runtime path order is explicit and release-first
- no public release documentation depends on repo-relative paths

### Phase 2: Bundle the runtime and packages

Files likely touched:
- `scripts/build-release.sh`
- possibly new helper packaging scripts

Tasks:
1. Add a packaging step that copies:
- `pose_server.py`
- model files
- bundled Python runtime
- required Python packages
2. Exclude local dev artifacts that should not ship.
3. Produce a verifiable app bundle layout.

Exit criteria:
- app bundle contains all helper runtime components
- no dependency on `/usr/bin/env python3` for public release

### Phase 3: Tighten runtime startup behavior

Files likely touched:
- `TurtleneckCoach/Core/MediaPipeClient.swift`
- `TurtleneckCoach/Core/PostureEngine.swift`

Tasks:
1. Prefer bundled runtime only in release flow.
2. Emit release-safe diagnostics when helper startup fails.
3. Fall back to Vision deterministically.
4. Ensure helper teardown still works after the packaging change.

Exit criteria:
- helper startup is deterministic on a clean machine
- fallback is explicit and non-destructive
- stop/quit teardown remains correct

### Phase 4: Validate on a clean machine

Tasks:
1. Install DMG on a clean Apple Silicon macOS 14+ account or machine.
2. Confirm helper starts without any preinstalled Python.
3. Confirm Vision fallback still works if helper is intentionally broken.
4. Confirm app stop/quit tears helper down.

Exit criteria:
- no system Python dependency
- no repo-relative dependency
- no stale helper after quit

## Verification Checklist

### Bundle contents
- [ ] `Contents/Resources/python_server/pose_server.py`
- [ ] `Contents/Resources/python_server/models/pose_landmarker_lite.task`
- [ ] `Contents/Resources/python_server/models/face_landmarker.task`
- [ ] bundled Python runtime path exists
- [ ] bundled Python package set exists

### Runtime
- [ ] helper launches from bundled runtime
- [ ] no `/usr/bin/env python3` dependency in public release path
- [ ] socket path connects successfully
- [ ] stop/quit tears helper down
- [ ] Vision fallback remains functional
- [x] vendored runtime smoke-imports `mediapipe` and `cv2` using bundled `PYTHONHOME` + `PYTHONPATH` on the development machine

### Release behavior
- [ ] no debug-only data capture required for normal operation
- [ ] no repo-relative paths required
- [ ] no preinstalled local venv required

## Risks

1. App size increase
- bundling Python and packages will make the app larger

2. Signing/runtime issues
- bundled executables and packages must work under the final signing/notarization flow

3. Runtime provenance
- the current vendored runtime is sourced from the local Xcode Python framework behind the development venv
- this is technically reproducible on the current machine, but should not be treated as acceptable for public redistribution

4. Dependency drift
- Python dependency versions must be pinned and reproducible

5. Operational complexity
- release build script becomes more complex and must be treated as the single supported release path

## Rollout Gate

This track should be considered complete only when:
1. the app bundle contains a fully self-contained MediaPipe runtime
2. that runtime is sourced from a distributable Python build rather than Xcode's bundled Python payload
3. stop/quit teardown still passes verification
4. release docs match the packaged runtime exactly
