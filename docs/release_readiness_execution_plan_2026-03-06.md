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

1. Implement MediaPipe self-contained packaging/runtime from `docs/mediapipe_self_contained_execution_plan_2026-03-06.md`.
2. Write the clean-machine DMG smoke checklist.
3. Execute clean-machine release QA once a suitable environment is available.
