# python-build-standalone Migration Plan

Date: 2026-03-06
Scope: replace Xcode-backed vendored Python runtime with a distributable runtime source for public DMG release
Current branch for follow-up work: `main` in `/Users/ilwonyoon/Documents/PT_turtle-release-followup`

## Why This Migration Is Needed

Current state:
- the app can vendor a working runtime from Xcode's `Python3.framework`
- that is good enough for local proof-of-concept validation
- it is not a safe basis for public DMG redistribution

Target state:
- the app bundles a distributable Python runtime source
- MediaPipe helper runs from that bundled runtime
- no dependency on system Python, repo paths, or Xcode payloads

## Constraints

1. Preserve calibration persistence invariants
- see [calibration_persistence_invariants_2026-03-06.md](/Users/ilwonyoon/Documents/PT_turtle-release-followup/docs/calibration_persistence_invariants_2026-03-06.md)

2. Preserve current release policy
- Apple Silicon (`arm64`) only
- macOS 14+

3. Keep Vision fallback working
- MediaPipe failure must not block app startup

## Runtime Source Choice

Recommended source:
- `python-build-standalone`

Why:
1. purpose-built for redistributable standalone Python builds
2. aligns with current `python_runtime/` + `python_packages/` bundle contract
3. avoids the Xcode-runtime provenance problem
4. minimizes changes to app-side launch logic already implemented

Current pinned candidate:
- release tag: `20260303`
- artifact: `cpython-3.11.15+20260303-aarch64-apple-darwin-install_only.tar.gz`
- fetch helper: [fetch-python-build-standalone.sh](/Users/ilwonyoon/Documents/PT_turtle-release-followup/scripts/fetch-python-build-standalone.sh)

Current validation status:
- artifact download/extract succeeded locally
- runtime root layout confirmed under extracted `python/`
- current `3.9` site-packages are not ABI-compatible with the `3.11` runtime
- rebuilding packages against the `3.11` standalone runtime succeeded locally
- `STRICT_SELF_CONTAINED_MEDIAPIPE=1 ./scripts/build-release.sh` now passes against the standalone runtime
- bundled `pose_server.py` was started directly from the built app using the bundled runtime and package paths
- package prep helper added: [prepare-python-packages.sh](/Users/ilwonyoon/Documents/PT_turtle-release-followup/scripts/prepare-python-packages.sh)

## Current Bundle Contract To Preserve

The app-side runtime code already expects roughly this:
- `Contents/Resources/python_server/pose_server.py`
- `Contents/Resources/python_server/models/...`
- `Contents/Resources/python_runtime/...`
- `Contents/Resources/python_packages/lib/pythonX.Y/site-packages/...`

The migration should keep this contract stable wherever possible.

## Implementation Phases

### Phase 1: Introduce a new runtime input source

Goal:
- stop sourcing vendored runtime bits from Xcode-backed `.venv`
- instead stage a `python-build-standalone` runtime into a reproducible local input directory

Tasks:
1. choose a pinned `python-build-standalone` artifact for `arm64-apple-darwin`
2. add an operator script to fetch/unpack it into a local cache or build input
3. document the pinned version and checksum

Status:
- initial candidate chosen
- fetch/unpack helper implemented
- release build can now auto-fetch the pinned runtime when the local standalone cache is missing

Expected outputs:
- a reproducible runtime source directory that can feed `prepare-python-runtime.sh`

### Phase 2: Adapt `prepare-python-runtime.sh`

Goal:
- make runtime prep source-agnostic
- support a standalone runtime source directly instead of inferring everything from `.venv`

Tasks:
1. allow runtime source path override
2. use runtime source for:
- interpreter binary
- stdlib
- dylib/framework payload
- resources
3. continue sourcing Python packages separately into `python_packages/`
4. keep smoke validation with:
- `PYTHONHOME`
- `PYTHONPATH`
- `mediapipe` import
- `cv2` import

### Phase 3: Rebuild Python packages against the new runtime

Goal:
- ensure bundled packages are compatible with the standalone runtime

Tasks:
1. create a clean environment with the chosen standalone runtime
2. install pinned helper dependencies there
3. materialize `python_packages/` from that environment
4. confirm native extensions import correctly under the standalone runtime

Status:
- this is now proven feasible on the development machine
- [prepare-python-packages.sh](/Users/ilwonyoon/Documents/PT_turtle-release-followup/scripts/prepare-python-packages.sh) is now wired into the release path

Risks:
- `opencv-python-headless` and `mediapipe` binary compatibility
- package size

### Phase 4: Release build integration

Goal:
- make `scripts/build-release.sh` consume the new runtime source by default

Tasks:
1. remove Xcode-runtime assumptions from the release path
2. keep strict mode enabled for release verification
3. ensure the final `.app` includes:
- `python_server/`
- `python_runtime/`
- `python_packages/`

Status:
- release build now stages a standalone runtime and rebuilt packages by default
- remaining work is provenance/compliance hardening and clean-account validation

### Phase 5: Validation

Goal:
- prove the new runtime works without touching existing user calibration

Validation checklist:
1. `STRICT_SELF_CONTAINED_MEDIAPIPE=1 ./scripts/build-release.sh` passes
2. vendored runtime smoke import passes
3. app bundle contains expected runtime/package layout
4. existing calibration remains readable after app update
5. MediaPipe helper starts from bundled runtime
6. Vision fallback still works when helper is broken on purpose
7. clean-account QA passes when environment is available

## No-Regression Rules

1. Do not change:
- `CFBundleIdentifier`
- `CalibrationManager.userDefaultsKey`
- `CalibrationData` backward decode behavior

2. Do not add runtime-migration code that clears calibration automatically

3. Do not make release startup depend on repo-relative files

## Deliverables

1. pinned standalone runtime source policy
2. runtime fetch/stage script
3. updated `prepare-python-runtime.sh`
4. updated `build-release.sh`
5. updated release-readiness docs
6. calibration-preservation verification note

## Exit Criteria

This migration is complete only when:
1. Xcode-backed runtime vendoring is no longer required for release
2. release build passes in strict self-contained mode
3. calibration persistence invariants are preserved
4. clean-account QA is the only remaining blocker
