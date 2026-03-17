# TurtleneckCoach Distribution Guide

This document defines the DMG distribution workflow for this repository’s current build architecture (`swiftc`-assembled app bundle, not `xcodebuild`).

## Release Entry Points

- Public landing page for installs/screenshots: [`README.md`](../README.md)
- Development/local app only: [`build.sh`](../build.sh)
- Public release app build/signing: [`scripts/build-release.sh`](../scripts/build-release.sh)
- DMG packaging: [`scripts/create-dmg.sh`](../scripts/create-dmg.sh)
- Notarization + stapling: [`scripts/notarize.sh`](../scripts/notarize.sh)

Important:
- Do not use `./build.sh` for public distribution.
- `./build.sh` produces an ad-hoc signed DEBUG app for local testing only.
- The supported public release path starts with `./scripts/build-release.sh "Developer ID Application: ..."`

## Current Distribution Model

- Build toolchain: direct `swiftc` build, app bundle assembled manually.
- Current release architecture policy: Apple Silicon (`arm64`) only.
- Current minimum supported OS for release: macOS 14.0+.
- Primary app output: `./TurtleneckCoach.app`
- Entitlements source: [`TurtleneckCoach/Resources/TurtleneckCoach.entitlements`](../TurtleneckCoach/Resources/TurtleneckCoach.entitlements)
- Info.plist source: [`TurtleneckCoach/Resources/Info.plist`](../TurtleneckCoach/Resources/Info.plist)
- Optional Python server source: `./python_server`
- MediaPipe is a product requirement for shipped turtle-neck tracking quality.
- Vision-only public releases are out of scope unless the product requirement changes explicitly.

This is not a universal build today. Intel Macs are out of scope for the current release path unless the build scripts are updated accordingly.

## Release Presentation Policy

- `README.md` is the product landing page for GitHub visitors.
- Reusable screenshots and logo assets live under [`docs/assets`](../docs/assets).
- GitHub Release assets should stay limited to the installer artifact unless there is a strong technical reason to upload more.
- Do not upload marketing screenshots to each release. Reference the checked-in assets from `README.md` instead.

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

### Release platform policy

- Public DMG releases currently target Apple Silicon Macs only.
- Release binaries are built for `arm64-apple-macos14`.
- Do not advertise Intel Mac support in release notes, installer copy, or distribution pages.
- If Intel support becomes a requirement later, add an explicit universal or separate x86_64 release path first.

### Python subprocess and Unix socket

- Current `MediaPipeClient` starts Python server and connects over `/tmp/pt_turtle.sock`.
- Candidate server paths currently include:
  - `~/.pt_turtle/server/pose_server.py`
  - `../python_server/pose_server.py` (dev mode)
  - `Contents/Resources/python_server/pose_server.py` (bundled mode)
- Release builds should bundle `python_server` into `Contents/Resources` to avoid dependency on repo layout.
- Release builds should also preserve bundled `python_runtime` and `python_packages` so MediaPipe remains functional after distribution.
- Do not respond to release issues by switching the public build to Vision-only; fix the bundled MediaPipe path instead.

### Hardened Runtime implications

- For Developer ID distribution, sign with hardened runtime (`--options runtime`).
- If Python runtime behavior breaks under hardened runtime:
  - [ ] Verify subprocess invocation path and execute permissions.
  - [ ] Prefer bundling/runtime pinning over reliance on user shell environment.
  - [ ] Treat broken bundled MediaPipe as a release blocker, not a reason to remove MediaPipe from the shipped build.

### Data and permissions

- Persistent data location: `~/Library/Application Support/TurtleneckCoach/` (migrated from `TurtleNeckDetector/`)
- Runtime socket: `/tmp/pt_turtle.sock`
- Current entitlement posture: sandbox disabled + camera entitlement.
- App Store migration will require replacing non-sandbox patterns (`/tmp` socket, unrestricted subprocess behavior).

## 4) Release Build Workflow (Checklist)

Use [`scripts/build-release.sh`](../scripts/build-release.sh).

### Ad-hoc test build (works today)

- [ ] Run:
  - [ ] `./scripts/build-release.sh`
- [ ] Confirm app output exists:
  - [ ] `./TurtleneckCoach.app`
- [ ] Confirm signature:
  - [ ] `codesign --verify --deep --strict --verbose=2 TurtleneckCoach.app`

### Developer ID release build

- [ ] Run with real identity:
  - [ ] `./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"`
- [ ] Confirm hardened runtime was enabled in script output.
- [ ] Verify signature:
  - [ ] `codesign --verify --deep --strict --verbose=2 TurtleneckCoach.app`

## 5) DMG Creation Workflow (Checklist)

Use [`scripts/create-dmg.sh`](../scripts/create-dmg.sh).

- [ ] Build and sign app first.
- [ ] Confirm the app is Developer ID signed for public release.
- [ ] Create DMG:
  - [ ] `./scripts/create-dmg.sh ./TurtleneckCoach.app`
- [ ] Confirm artifact naming:
  - [ ] `TurtleneckCoach-{version}.dmg`
- [ ] Confirm DMG contains:
  - [ ] `TurtleneckCoach.app`
  - [ ] `Applications` symlink
- [ ] Confirm volume name includes version.
- [ ] Confirm volume icon is applied (custom icon bit + `.VolumeIcon.icns` in image source).

## 6) Notarization Workflow (notarytool) Checklist

Use [`scripts/notarize.sh`](../scripts/notarize.sh).

### One-time credential setup (recommended)

- [ ] Store keychain profile:
  - [ ] `xcrun notarytool store-credentials "turtle-notary" --apple-id "<apple-id>" --team-id "<team-id>" --password "<app-specific-password>"`
- [ ] Validate:
  - [ ] `xcrun notarytool history --keychain-profile "turtle-notary"`

### Submit, wait, and staple

- [ ] Submit and wait:
  - [ ] `./scripts/notarize.sh ./TurtleneckCoach-1.0.0.dmg turtle-notary`
- [ ] Confirm status is `Accepted`.
- [ ] Staple ticket:
  - [ ] handled by script (`xcrun stapler staple`)
- [ ] Validate staple:
  - [ ] handled by script (`xcrun stapler validate`)

## 7) Final Verification Checklist

- [ ] Verify app signature:
  - [ ] `codesign --verify --deep --strict --verbose=2 TurtleneckCoach.app`
- [ ] Verify DMG integrity:
  - [ ] `hdiutil verify TurtleneckCoach-<version>.dmg`
- [ ] Verify staple:
  - [ ] `xcrun stapler validate -v TurtleneckCoach-<version>.dmg`
- [ ] Optional Gatekeeper assessment:
  - [ ] `spctl --assess --type open --context context:primary-signature --verbose=4 TurtleneckCoach-<version>.dmg`
- [ ] Smoke-test installation on a clean macOS user account.

## 8) GitHub Release Page Structure

Use GitHub Releases as the changelog + download surface, not as the full product landing page.

### Recommended release body

- Release title: `Turtleneck Coach vX.Y.Z`
- One short summary sentence
- `### Highlights` with 3-5 bullets
- Optional install/reminder note if requirements changed
- Link readers back to [`README.md`](../README.md) for screenshots, product tour, and positioning copy

### Asset policy

- Upload the notarized DMG as the main public release asset.
- Keep screenshots/logo in [`docs/assets`](../docs/assets) and reference them from [`README.md`](../README.md).
- Do not upload marketing screenshots to each release unless the image itself is the thing being distributed.

### Manual publishing checklist

- Build and sign with [`scripts/build-release.sh`](../scripts/build-release.sh).
- Package with [`scripts/create-dmg.sh`](../scripts/create-dmg.sh).
- Notarize with [`scripts/notarize.sh`](../scripts/notarize.sh).
- Create the GitHub Release manually with a concise changelog-focused body.
- Upload the notarized DMG only.

## 9) Sparkle Auto-Update Integration (Future)

### Checklist

- [ ] Add Sparkle framework and updater UI flow.
- [ ] Generate Sparkle EdDSA keys and keep private key secure.
- [ ] Publish signed appcast feed (`appcast.xml`) over HTTPS.
- [ ] Produce signed update archives (`.zip`) for each release.
- [ ] Ensure every update payload is notarized and stapled.
- [ ] Add release CI pipeline for build -> sign -> notarize -> appcast publish.

## 10) Mac App Store Migration Path (Future)

### Checklist

- [ ] Enable App Sandbox and remove unsupported entitlements/behaviors.
- [ ] Replace `/tmp` Unix socket architecture with sandbox-compatible IPC (for example XPC or app-group-based design).
- [ ] Replace unrestricted subprocess assumptions (embedded Python strategy may not be MAS-compliant).
- [ ] Add required privacy usage descriptions and sandbox file access patterns.
- [ ] Transition signing from Developer ID to Mac App Store distribution cert/profile.
- [ ] Archive and submit via App Store Connect pipeline.

## 11) Recommended Command Sequence

```bash
# 0) Do not use ./build.sh for public release. It is dev-only.

# 1) Build/sign app with Developer ID
./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"

# 2) Create DMG from the signed app
./scripts/create-dmg.sh ./TurtleneckCoach.app

# 3) Notarize + staple
./scripts/notarize.sh ./TurtleneckCoach-1.0.0.dmg turtle-notary
```
