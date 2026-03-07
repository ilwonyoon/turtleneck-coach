# Clean-Machine QA Without a Second Mac

Date: 2026-03-06
Scope: pre-release validation when no spare Mac is available
Status: fallback procedure, not a substitute for eventual clean-machine release signoff

## Goal

Reduce false confidence from a developer-contaminated machine when a second clean Mac is not available.

## Recommended Order

1. Fresh macOS user account on the same Mac
2. Existing Mac user after explicit state reset
3. Final public-release signoff only after a true clean account or second machine is available

## Option 1: Fresh macOS User Account on the Same Mac

This is the closest practical substitute for a second Mac.

Why it helps:
- no existing app preferences
- no prior camera permission state for the app
- no pre-existing app support files
- no stale helper/socket state under the user account

### Setup

1. Create a new standard macOS user account.
2. Log into that account.
3. Do not install dev tools or clone the repo there.
4. Copy only the DMG you want to validate.

### Runbook

1. Open the DMG.
2. Drag the app into `Applications`.
3. Launch the app from `Applications`.
4. Accept the camera permission prompt.
5. Complete onboarding and calibration.
6. Start monitoring.
7. Switch `Camera Position` manually and verify recalibration behavior.
8. Stop monitoring.
9. Quit and relaunch the app.
10. Confirm helper restart/teardown behavior is sane.

### What this still does not prove

1. It does not simulate a different hardware model.
2. It does not replace later notarized-DMG validation.
3. It may still share some machine-level dependencies if they are globally installed.

## Option 2: Same User Account With Explicit Reset

Use this only when creating a fresh macOS user is not feasible.

### Reset Checklist

1. Remove the app from `Applications`.
2. Delete app preferences and support data for the app bundle id.
3. Clear any app-specific caches.
4. Reset camera permission for the app using `tccutil` if needed.
5. Kill any lingering helper processes.
6. Remove any old temporary sockets and debug logs.

### Suggested commands

Run these carefully and verify bundle identifiers before use.

```bash
pkill -f TurtleneckCoach || true
pkill -f pose_server.py || true
rm -f /tmp/pt_turtle.sock /tmp/turtle_cvadebug.log
rm -rf ~/Library/Application\ Support/TurtleneckCoach
rm -f ~/Library/Preferences/com.turtleneck.detector.plist
```

If camera permission needs to be reset:

```bash
tccutil reset Camera com.turtleneck.detector
```

Then:

1. Mount the DMG.
2. Reinstall the app into `Applications`.
3. Launch and validate first-run behavior again.

### Limits of this method

1. It is weaker than a fresh macOS user.
2. Global Python or developer tools may still mask packaging problems.
3. It is not sufficient as the only signoff for a public release.

## Practical Release Policy

If no second Mac is available, use this progression:

1. Finish engineering work.
2. Validate with a fresh macOS user on the same Mac.
3. Treat public-release signoff as pending until one true clean-account run is completed.

## Recommendation for This Project

For `TurtleneckCoach`, the minimum acceptable substitute before public DMG release is:

1. fresh macOS user account on the same Apple Silicon machine
2. release DMG install from `Applications`
3. no repo checkout or local dev virtualenv visible to that user
4. manual verification that MediaPipe starts without relying on the developer shell environment

This is still a fallback. Final release confidence should be upgraded later with a true clean-account or second-machine run.
