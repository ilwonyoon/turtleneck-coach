# macOS Release Readiness Execution Plan

Date: 2026-03-06
Branch baseline: `main`
Release target: public macOS DMG
Out of scope for this phase: Apple Developer account setup, notarization credential setup, final paid-program enrollment steps

## Goal

Ship a macOS DMG only after the app passes non-Apple release blockers for:
- packaging and operator safety
- privacy/compliance consistency
- runtime hygiene, performance, and battery
- final QA gates

This document is the master execution plan. Track-specific changes should update this document as blockers are resolved.

## Current Go/No-Go Status

Status: `No-Go`

Blocking categories:
1. Python/MediaPipe release runtime is not yet fully self-contained for clean-machine distribution.
2. Clean-machine release QA checklist and smoke execution are not finished.
3. Apple signing/notarization execution remains deferred.

## Deferred Until Later

These items are intentionally deferred and are not blockers for the current engineering pass:
1. Apple Developer Program account enrollment/admin cleanup
2. Developer ID certificate acquisition
3. Notary credential setup in keychain
4. Final notarization submission to Apple
5. Clean-machine QA execution until a suitable test Mac or fresh macOS account is available

Fallback guidance when no second Mac is available:
- `docs/clean_machine_qa_fallback_2026-03-06.md`

## Track Ownership

Track A: Release docs and distribution flow
- Files:
  - `docs/release_readiness_execution_plan_2026-03-06.md`
  - `docs/DISTRIBUTION.md`
  - `build.sh`
  - `scripts/build-release.sh`
  - `scripts/create-dmg.sh`
  - `scripts/notarize.sh`
- Goal:
  - Make the official release entrypoint unambiguous.
  - Prevent accidental use of dev build flow for public release.

Track B: Privacy and compliance consistency
- Files:
  - `TurtleneckCoach/Resources/Info.plist`
  - `docs/privacy-policy.md`
  - user-facing disclosure docs if needed
- Goal:
  - Align app metadata, privacy claims, and actual storage/runtime behavior.

Track C: Runtime hygiene and release behavior
- Files:
  - `TurtleneckCoach/Core/PostureEngine.swift`
  - `TurtleneckCoach/Core/MediaPipeClient.swift`
  - related tests/docs if needed
- Goal:
  - Ensure helper shutdown and release-safe stop/quit behavior.

Master-only integration files:
- `docs/release_readiness_execution_plan_2026-03-06.md`
- any cross-track wording conflicts
- final merge summary and release gate status

## Quality Gates

### Track Gate
- Scope matches assigned track.
- Build passes for touched targets.
- Relevant tests or verification notes updated.
- Risk notes and rollback note recorded.

### Integration Gate
- `./build.sh` passes.
- Any touched test harness passes.
- No unresolved release blockers remain in tracks A-C.
- Docs match actual code paths.

### Release Gate
- App can be built through the documented release path.
- Release path is clearly separated from dev/debug path.
- Privacy usage strings, policy, and behavior are aligned.
- Helper process stops on app stop/quit.
- Clean-machine smoke checklist is documented.

## Execution Order

1. Track A: clarify release path and docs
2. Track B: privacy/compliance cleanup
3. Track C: runtime hygiene fix
4. Master integration review
5. Final release checklist authoring for clean-machine smoke and notarization handoff

## Blocking Checklist

### A. Release flow clarity
- [x] `build.sh` is explicitly documented as dev-only.
- [x] `docs/DISTRIBUTION.md` uses current repo paths.
- [x] Release docs point only to `scripts/build-release.sh`, `scripts/create-dmg.sh`, `scripts/notarize.sh`.
- [x] Architecture policy is explicit (`arm64` only or broader support decision).

### B. Privacy/compliance consistency
- [x] Remove stale `NSDocumentsFolderUsageDescription` if no longer needed.
- [x] Camera usage string matches actual behavior.
- [x] Privacy policy distinguishes release behavior from debug-only data capture.
- [x] Public repo policy for `debug_data/` is explicitly decided.

### C. Runtime hygiene
- [x] Stop/quit path guarantees MediaPipe helper teardown in code.
- [x] Release behavior does not depend on lingering helper state.
- [x] Verification notes exist for stop/restart/reopen flows.

### D. Final handoff prep
- [ ] Clean-machine QA checklist written.
- [ ] Notarization handoff section written for later execution.
- [ ] Go/No-Go status updated after each track lands.

### E. MediaPipe self-contained packaging prep
- [x] A reproducible prep script exists for materializing bundled Python layout from `python_server/.venv`.
- [x] Release build path can consume prepared Python runtime/package layout.
- [x] Prepared runtime now vendors the interpreter, `Python3` dylib, stdlib, and framework resources from the Xcode Python framework source backing the local venv.
- [ ] Bundled MediaPipe runtime is validated on a clean machine after DMG install.
- [ ] Clean-machine startup is validated with bundled MediaPipe assets only.

## Verification Notes Template

For each landed track, record:
- What changed
- How it was verified
- Remaining risks
- Rollback plan

## Progress Log

### 2026-03-06
- Initial plan created.
- Apple account/notary enrollment explicitly deferred.
- First execution batch opened for tracks A-C.
- Track A landed:
  - `build.sh` marked dev-only
  - release entrypoints clarified
  - distribution paths corrected
  - ad-hoc DMG creation blocked by default
- Track B landed:
  - `Info.plist` privacy strings aligned more closely to current app behavior
  - privacy policy updated to distinguish public release behavior from debug/internal builds
- Track C landed:
  - stop/quit paths now shut down the MediaPipe helper
  - verification notes added in `docs/mediapipe_shutdown_verification_2026-03-06.md`
- Remaining blockers after batch 1:
  - decide public handling of `debug_data/`
  - verify clean-machine release QA flow

### 2026-03-06 (batch 2)
- Track A follow-up landed:
  - release docs now explicitly state `Apple Silicon (arm64) / macOS 14+` policy
  - Intel support is explicitly out of scope for the current release path
- Track B follow-up landed:
  - `NSDocumentsFolderUsageDescription` removed from `Info.plist`
  - privacy policy wording updated to reflect user-initiated export without direct Documents entitlement copy
- Remaining blockers after batch 2:
  - write and execute clean-machine release QA checklist

### 2026-03-06 (batch 3)
- `debug_data/` policy decided:
  - repo tracking removed
  - local files remain on disk
  - `.gitignore` updated to keep future debug captures local-only
- Intel support explicitly dropped for this release phase
- Clean-machine QA execution is blocked by environment for now; checklist still remains to be written and executed later
- MediaPipe self-contained workstream documented in:
  - `docs/mediapipe_self_contained_execution_plan_2026-03-06.md`
- Remaining blockers after batch 3:
  - implement MediaPipe self-contained packaging/runtime
  - write clean-machine release QA checklist
  - execute clean-machine release QA once a suitable environment is available

### 2026-03-06 (batch 4, in progress)
- MediaPipe self-contained phase 1 started:
  - release runtime now prefers bundled `python_server` and bundled `python_runtime`
  - dev-oriented runtime/script fallbacks are constrained to DEBUG paths
  - release build script now has explicit hooks for bundling `python_runtime/` and `python_packages/`
- Verification so far:
  - `./build.sh` passed
  - `test_logic.swift` passed (`71/71`)
- Remaining work inside this track:
  - provide actual bundled runtime/package layout
  - validate clean-machine startup without system Python

### 2026-03-06 (batch 5)
- Track A MediaPipe packaging prep landed:
  - added `scripts/prepare-python-runtime.sh`
  - release build can now materialize `python_runtime/` + `python_packages/` from local `python_server/.venv`
  - release build warns if the prepared runtime provenance is the local Xcode Python framework
  - strict mode added: `STRICT_SELF_CONTAINED_MEDIAPIPE=1`
- Current limitation discovered from local assets:
  - `python_server/.venv/bin/python3` resolves to Xcode's bundled Python
  - this means the vendored release runtime currently derives from local Xcode assets and still needs clean-machine validation before public release
- Remaining blockers after batch 5:
  - validate DMG-installed startup on a clean machine without repo or shell-PATH help

### 2026-03-06 (batch 6)
- Track A MediaPipe vendoring follow-up landed:
  - `scripts/prepare-python-runtime.sh` now vendors the Xcode Python framework payload behind the local venv instead of copying only the resolved executable
  - prepared `python_runtime/` now includes:
    - `bin/python3`
    - `Python3`
    - `lib/python3.9/` stdlib
    - `Resources/`
  - strict mode now validates vendoring completeness rather than failing purely because the venv resolves into Xcode
- Remaining blockers after batch 6:
  - validate DMG-installed startup on a clean machine without repo or shell-PATH help
  - confirm notarized release behavior with vendored Python runtime once Apple account work is unblocked

### 2026-03-06 (batch 7)
- Track A/Track C integration landed:
  - vendored runtime prep now runs a smoke import against the prepared runtime using:
    - `PYTHONHOME=<python_runtime>`
    - `PYTHONPATH=<python_packages>/lib/python3.9/site-packages`
  - strict prep verification passed locally with:
    - `REQUIRE_COMPLETE_VENDORING=1 ./scripts/prepare-python-runtime.sh`
  - strict release build path passed locally with:
    - `STRICT_SELF_CONTAINED_MEDIAPIPE=1 ./scripts/build-release.sh`
  - `MediaPipeClient` now launches the bundled helper with explicit bundled runtime environment:
    - `PYTHONHOME`
    - `PYTHONPATH`
    - `DYLD_LIBRARY_PATH` / `DYLD_FALLBACK_LIBRARY_PATH` when needed
- Remaining blockers after batch 7:
  - execute clean-account QA against the DMG/app install path
  - replace the currently vendored Xcode Python payload with a separately sourced distributable runtime before public DMG release

### 2026-03-06 (batch 8)
- Distribution-policy review completed against Apple's official Xcode terms:
  - current vendored runtime is sourced from Xcode's `Python3.framework`
  - this should be treated as `No-Go` for public DMG distribution
- Basis:
  - the Xcode and Apple SDKs Agreement describes Apple Software as licensed for internal use
  - the same agreement restricts redistribution of Apple Software, in whole or in part, unless otherwise expressly permitted by Apple in writing
- Release policy decision:
  - keep the vendored Xcode-backed runtime only as a local engineering proof-of-concept
  - do not ship it in a public DMG
  - replace it with a separately sourced distributable Python runtime before release

## Batch 1 Verification

### Integrated verification
- `bash -n build.sh scripts/build-release.sh scripts/create-dmg.sh scripts/notarize.sh` passed
- `plutil -lint TurtleneckCoach/Resources/Info.plist` passed
- `./build.sh` passed
- `test_logic.swift` passed (`71/71`)

### Track A verification notes
- `./build.sh --help` shows dev-only guidance
- `./scripts/build-release.sh --help` shows release path guidance
- `./scripts/create-dmg.sh ./TurtleneckCoach.app` now blocks ad-hoc DMG creation by default
- `./scripts/notarize.sh ./TurtleneckCoach.app` now fails fast with DMG guidance

### Track B verification notes
- privacy copy aligned to:
  - local camera processing
  - local session storage
  - user-initiated JSON export
  - debug-only `/tmp` diagnostics for internal builds

### Track C verification notes
- helper shutdown behavior documented in `docs/mediapipe_shutdown_verification_2026-03-06.md`
- code now requests helper teardown on monitoring stop and app termination

## Next Batch

1. Re-run `scripts/prepare-python-runtime.sh` and confirm `VALIDATION.txt` shows a complete vendored runtime layout.
2. Re-run `scripts/build-release.sh` with `STRICT_SELF_CONTAINED_MEDIAPIPE=1`.
3. Write the clean-machine DMG smoke checklist.
4. Execute clean-machine release QA once a suitable environment is available.
5. Confirm whether the vendored Xcode Python payload is acceptable for public distribution or needs replacement with a separately sourced runtime.

## Operator Steps For Current MediaPipe Packaging Prep

These steps now vendor the currently available Xcode-backed Python framework assets into a bundle-shaped runtime layout. They do not yet replace clean-machine QA or final distribution-policy review.

1. Prepare bundled Python layout from the local venv:
   - `./scripts/prepare-python-runtime.sh`
2. Review the output:
   - `build/python_bundle_prep/python_runtime/`
   - `build/python_bundle_prep/python_packages/`
   - `build/python_bundle_prep/VALIDATION.txt`
3. Confirm the vendored runtime payload exists:
   - `build/python_bundle_prep/python_runtime/bin/python3`
   - `build/python_bundle_prep/python_runtime/Python3`
   - `build/python_bundle_prep/python_runtime/lib/python3.9/`
   - `build/python_bundle_prep/python_runtime/Resources/`
4. Review provenance and validation notes:
   - `build/python_bundle_prep/python_runtime/XCODE_FRAMEWORK_SOURCE.txt`
   - `build/python_bundle_prep/VALIDATION.txt`
5. If you want the prep step to fail unless the vendored runtime layout is complete:
   - `REQUIRE_COMPLETE_VENDORING=1 ./scripts/prepare-python-runtime.sh`
6. Build the release app:
   - `./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"`
7. To enforce strict failure for incomplete vendoring during the release build:
   - `STRICT_SELF_CONTAINED_MEDIAPIPE=1 ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"`
8. Before public release, still require:
   - DMG-installed startup validation on a clean machine
   - final signing/notarization once Apple account setup is unblocked

## Current Limitations

1. The vendored runtime currently derives from the local Xcode Python framework source, so public-distribution acceptability still needs an explicit policy decision.
2. Clean-machine behavior is still unproven until the DMG-installed app is validated without repo, PATH, or local developer-tool assistance.
3. Apple signing/notarization execution is still deferred for this planning phase.
