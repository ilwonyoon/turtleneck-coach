# Calibration Persistence Invariants

Date: 2026-03-06
Scope: MediaPipe runtime replacement work
Goal: guarantee that replacing the bundled Python runtime does not silently discard existing user calibration data

## Current Storage Contract

### Bundle identity
- `CFBundleIdentifier = com.turtleneck.detector`
- Source: [Info.plist](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Resources/Info.plist)

This is the namespace boundary for `UserDefaults.standard`. If this changes, existing saved calibration will no longer be read from the same defaults domain.

### Calibration storage key
- `CalibrationManager.userDefaultsKey = "calibrationData"`
- Source: [CalibrationManager.swift](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Core/CalibrationManager.swift)

### Calibration payload format
- type: `CalibrationData`
- encoding: `JSONEncoder` / `JSONDecoder`
- storage: `UserDefaults.standard.data(forKey: "calibrationData")`
- source: [CalibrationData.swift](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Models/CalibrationData.swift), [CalibrationManager.swift](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Core/CalibrationManager.swift)

### Schema behavior
- current emitted schema: `schemaVersion = 2`
- decoder remains backward-compatible using `decodeIfPresent(... ) ?? default`
- source: [CalibrationData.swift](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Models/CalibrationData.swift)

## Current Destructive Path

Saved calibration is explicitly cleared only by:
- `CalibrationManager.clearSaved()`
- called from `PostureEngine.resetCalibration()`
- source: [CalibrationManager.swift](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Core/CalibrationManager.swift), [PostureEngine.swift](/Users/ilwonyoon/Documents/PT_turtle-release-followup/TurtleneckCoach/Core/PostureEngine.swift)

Important distinction:
- `cameraContextSelection` changes trigger recalibration flow and mark calibration stale
- they do not directly delete the saved `calibrationData` payload unless `resetCalibration()` is explicitly invoked

## Runtime-Replacement Safety Invariants

The `python-build-standalone` migration must preserve all of the following:

1. `CFBundleIdentifier` must remain `com.turtleneck.detector`
2. `CalibrationManager.userDefaultsKey` must remain `calibrationData`
3. `CalibrationData` must remain backward-decodable for existing schema `1` and `2` payloads
4. MediaPipe/runtime replacement must not call `CalibrationManager.clearSaved()` as part of installation, startup, runtime probing, fallback, or migration
5. Failure to launch MediaPipe must not clear calibration
6. `cameraContextSelection` changes may mark calibration stale or restart calibration, but must not silently wipe stored calibration
7. Release build scripts must not modify user defaults or app support state

## Allowed Changes During Runtime Migration

These are safe if the invariants above remain true:

1. Replace bundled Python runtime source
2. Replace helper launch environment (`PYTHONHOME`, `PYTHONPATH`, dylib paths)
3. Change MediaPipe helper packaging layout inside the app bundle
4. Improve startup/fallback logic
5. Add release diagnostics

## Unsafe Changes Requiring Explicit Migration Plan

1. Renaming `calibrationData`
2. Changing bundle identifier
3. Changing `CalibrationData` serialization in a way that breaks old payload decode
4. Auto-resetting calibration on first run after runtime migration
5. Coupling runtime health checks to destructive calibration reset

## Pre-Implementation Gate

Before any `python-build-standalone` code lands, verify:

1. `CalibrationManager.userDefaultsKey` unchanged
2. `CFBundleIdentifier` unchanged
3. `CalibrationData(from:)` still decodes old values with defaults
4. no new call sites for `CalibrationManager.clearSaved()` were introduced

## Post-Implementation Gate

After runtime migration lands, verify on a machine that already has a saved calibration:

1. launch updated app
2. confirm `calibrationData` loads without requiring reset
3. confirm posture scoring starts from existing baseline
4. confirm MediaPipe helper launch success/failure does not wipe baseline
5. confirm manual `Reset Calibration` still clears baseline only when explicitly invoked

## Release Recommendation

Treat calibration persistence as a release-blocking invariant.
A Python runtime migration is acceptable only if it is proven to be non-destructive to the existing `calibrationData` payload.
