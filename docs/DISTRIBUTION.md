# TurtleNeckDetector Distribution Guide

This document defines a practical DMG distribution workflow for this repository’s current build architecture (`swiftc` via [`build.sh`](/Users/ilwonyoon/Documents/Turtle_neck_detector/build.sh), not `xcodebuild`).

## Current Distribution Model

- Build toolchain: direct `swiftc` build, app bundle assembled manually.
- Primary app output: `/Users/ilwonyoon/Documents/Turtle_neck_detector/TurtleNeckDetector.app`
- Entitlements source: [`TurtleNeckDetector/Resources/TurtleNeckDetector.entitlements`](/Users/ilwonyoon/Documents/Turtle_neck_detector/TurtleNeckDetector/Resources/TurtleNeckDetector.entitlements)
- Info.plist source: [`TurtleNeckDetector/Resources/Info.plist`](/Users/ilwonyoon/Documents/Turtle_neck_detector/TurtleNeckDetector/Resources/Info.plist)
- Optional Python server: `/Users/ilwonyoon/Documents/Turtle_neck_detector/python_server`

## 1) Prerequisites Checklist

- [ ] Apple Developer Program membership is active (required for Developer ID signing + notarization).
- [ ] Xcode + Command Line Tools installed (`xcode-select -p` works).
- [ ] `xcrun notarytool` available (`xcrun notarytool --help` works).
- [ ] Developer ID Application certificate installed in login keychain.
- [ ] Signing identity confirmed:
  - [ ] `security find-identity -v -p codesigning`
- [ ] App-specific password or API key strategy decided for notarization.

## 2) Obtain Developer ID Application Certificate (Step-by-Step)

### Checklist

- [ ] Sign in to <https://developer.apple.com/account/> with the team that will ship the app.
- [ ] Create a Certificate Signing Request (CSR):
  - [ ] Open **Keychain Access**.
  - [ ] `Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority`.
  - [ ] Save CSR to disk.
- [ ] Create certificate in Apple Developer portal:
  - [ ] Go to **Certificates, IDs & Profiles**.
  - [ ] Click **Certificates** then **+**.
  - [ ] Select **Developer ID Application**.
  - [ ] Upload CSR.
- [ ] Download generated `.cer`.
- [ ] Install `.cer` by opening it (imports to Keychain).
- [ ] Verify identity string:
  - [ ] `security find-identity -v -p codesigning | rg "Developer ID Application"`
- [ ] Copy exact identity string for release signing:
  - [ ] Example: `Developer ID Application: Your Name (TEAMID)`

## 3) Architecture Considerations Before Public Distribution

### Python subprocess and Unix socket

- Current `MediaPipeClient` starts Python server and connects over `/tmp/pt_turtle.sock`.
- Candidate server paths currently include:
  - `~/.pt_turtle/server/pose_server.py`
  - `../python_server/pose_server.py` (dev mode)
  - `Contents/Resources/python_server/pose_server.py` (bundled mode)
- Release builds should bundle `python_server` into `Contents/Resources` to avoid dependency on repo layout.

### Hardened Runtime implications

- For Developer ID distribution, sign with hardened runtime (`--options runtime`).
- If Python runtime behavior breaks under hardened runtime:
  - [ ] Verify subprocess invocation path and execute permissions.
  - [ ] Prefer bundling/runtime pinning over reliance on user shell environment.
  - [ ] Consider native Vision-only mode fallback when Python server unavailable.

### Data and permissions

- Persistent data location: `~/Library/Application Support/TurtleNeckDetector/`
- Runtime socket: `/tmp/pt_turtle.sock`
- Current entitlement posture: sandbox disabled + camera entitlement.
- App Store migration will require replacing non-sandbox patterns (`/tmp` socket, unrestricted subprocess behavior).

## 4) Release Build Workflow (Checklist)

Use [`scripts/build-release.sh`](/Users/ilwonyoon/Documents/Turtle_neck_detector/scripts/build-release.sh).

### Ad-hoc test build (works today)

- [ ] Run:
  - [ ] `./scripts/build-release.sh`
- [ ] Confirm app output exists:
  - [ ] `/Users/ilwonyoon/Documents/Turtle_neck_detector/TurtleNeckDetector.app`
- [ ] Confirm signature:
  - [ ] `codesign --verify --deep --strict --verbose=2 TurtleNeckDetector.app`

### Developer ID release build

- [ ] Run with real identity:
  - [ ] `./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"`
- [ ] Confirm hardened runtime was enabled in script output.
- [ ] Verify signature:
  - [ ] `codesign --verify --deep --strict --verbose=2 TurtleNeckDetector.app`

## 5) DMG Creation Workflow (Checklist)

Use [`scripts/create-dmg.sh`](/Users/ilwonyoon/Documents/Turtle_neck_detector/scripts/create-dmg.sh).

- [ ] Build and sign app first.
- [ ] Create DMG:
  - [ ] `./scripts/create-dmg.sh ./TurtleNeckDetector.app`
- [ ] Confirm artifact naming:
  - [ ] `TurtleNeckDetector-{version}.dmg`
- [ ] Confirm DMG contains:
  - [ ] `TurtleNeckDetector.app`
  - [ ] `Applications` symlink
- [ ] Confirm volume name includes version.
- [ ] Confirm volume icon is applied (custom icon bit + `.VolumeIcon.icns` in image source).

## 6) Notarization Workflow (notarytool) Checklist

Use [`scripts/notarize.sh`](/Users/ilwonyoon/Documents/Turtle_neck_detector/scripts/notarize.sh).

### One-time credential setup (recommended)

- [ ] Store keychain profile:
  - [ ] `xcrun notarytool store-credentials "turtle-notary" --apple-id "<apple-id>" --team-id "<team-id>" --password "<app-specific-password>"`
- [ ] Validate:
  - [ ] `xcrun notarytool history --keychain-profile "turtle-notary"`

### Submit, wait, and staple

- [ ] Submit and wait:
  - [ ] `./scripts/notarize.sh ./TurtleNeckDetector-1.0.0.dmg turtle-notary`
- [ ] Confirm status is `Accepted`.
- [ ] Staple ticket:
  - [ ] handled by script (`xcrun stapler staple`)
- [ ] Validate staple:
  - [ ] handled by script (`xcrun stapler validate`)

## 7) Final Verification Checklist

- [ ] Verify app signature:
  - [ ] `codesign --verify --deep --strict --verbose=2 TurtleNeckDetector.app`
- [ ] Verify DMG integrity:
  - [ ] `hdiutil verify TurtleNeckDetector-<version>.dmg`
- [ ] Verify staple:
  - [ ] `xcrun stapler validate -v TurtleNeckDetector-<version>.dmg`
- [ ] Optional Gatekeeper assessment:
  - [ ] `spctl --assess --type open --context context:primary-signature --verbose=4 TurtleNeckDetector-<version>.dmg`
- [ ] Smoke-test installation on a clean macOS user account.

## 8) Sparkle Auto-Update Integration (Future)

### Checklist

- [ ] Add Sparkle framework and updater UI flow.
- [ ] Generate Sparkle EdDSA keys and keep private key secure.
- [ ] Publish signed appcast feed (`appcast.xml`) over HTTPS.
- [ ] Produce signed update archives (`.zip`) for each release.
- [ ] Ensure every update payload is notarized and stapled.
- [ ] Add release CI pipeline for build -> sign -> notarize -> appcast publish.

## 9) Mac App Store Migration Path (Future)

### Checklist

- [ ] Enable App Sandbox and remove unsupported entitlements/behaviors.
- [ ] Replace `/tmp` Unix socket architecture with sandbox-compatible IPC (for example XPC or app-group-based design).
- [ ] Replace unrestricted subprocess assumptions (embedded Python strategy may not be MAS-compliant).
- [ ] Add required privacy usage descriptions and sandbox file access patterns.
- [ ] Transition signing from Developer ID to Mac App Store distribution cert/profile.
- [ ] Archive and submit via App Store Connect pipeline.

## 10) Recommended Command Sequence

```bash
# 1) Build/sign app (ad-hoc test mode today)
./scripts/build-release.sh

# 2) Create DMG
./scripts/create-dmg.sh ./TurtleNeckDetector.app

# 3) Notarize + staple (after Developer ID cert + credentials are set)
./scripts/notarize.sh ./TurtleNeckDetector-1.0.0.dmg turtle-notary
```
