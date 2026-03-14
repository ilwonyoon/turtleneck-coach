#!/bin/bash
# Development build only.
# Produces a local debug app with ad-hoc signing for fast iteration.
# Do NOT use this script for Developer ID signing, notarization, or DMG release.
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
cat <<'USAGE'
Usage: ./build.sh

Development-only build:
  - DEBUG compile
  - ad-hoc signing (-)
  - local app launch/testing

Production DMG release:
  ./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"
  ./scripts/create-dmg.sh ./TurtleneckCoach.app
  ./scripts/notarize.sh ./TurtleneckCoach-<version>.dmg <keychain-profile>
USAGE
exit 0
fi

echo "Building TurtleneckCoach (development build)..."
echo "warning: build.sh is dev-only and produces an ad-hoc signed DEBUG app."
echo "warning: for any public DMG/notarized release, use ./scripts/build-release.sh instead."

# Ensure app bundle structure exists
mkdir -p TurtleneckCoach.app/Contents/MacOS
mkdir -p TurtleneckCoach.app/Contents/Resources

# Copy app icon
cp TurtleneckCoach/Resources/AppIcon.icns TurtleneckCoach.app/Contents/Resources/AppIcon.icns

# Always copy the canonical plist so local builds match current app metadata.
cp TurtleneckCoach/Resources/Info.plist TurtleneckCoach.app/Contents/Info.plist

swiftc \
  TurtleneckCoach/DesignSystem/DesignTokens.swift \
  TurtleneckCoach/Core/CalibrationManager.swift \
  TurtleneckCoach/Core/CameraManager.swift \
  TurtleneckCoach/Core/DebugLogWriter.swift \
  TurtleneckCoach/Core/MediaPipeClient.swift \
  TurtleneckCoach/Core/PostureAnalyzer.swift \
  TurtleneckCoach/Core/PostureClassifier.swift \
  TurtleneckCoach/Core/PostureDataStore.swift \
  TurtleneckCoach/Core/PostureEngine.swift \
  TurtleneckCoach/Core/VisionPoseDetector.swift \
  TurtleneckCoach/Models/CalibrationData.swift \
  TurtleneckCoach/Models/CameraSourceMode.swift \
  TurtleneckCoach/Models/CameraPosition.swift \
  TurtleneckCoach/Models/CameraContext.swift \
  TurtleneckCoach/Models/PostureMetrics.swift \
  TurtleneckCoach/Models/PostureState.swift \
  TurtleneckCoach/Services/FeedbackEngine.swift \
  TurtleneckCoach/Services/DashboardMessages.swift \
  TurtleneckCoach/Services/CoachingTips.swift \
  TurtleneckCoach/Services/NotificationService.swift \
  TurtleneckCoach/TurtleneckCoachApp.swift \
  TurtleneckCoach/Views/CalibrationView.swift \
  TurtleneckCoach/Views/CameraPreviewView.swift \
  TurtleneckCoach/Views/DashboardView.swift \
  TurtleneckCoach/Views/DashboardWindowController.swift \
  TurtleneckCoach/Views/MenuBarView.swift \
  TurtleneckCoach/Views/PostureScoreView.swift \
  TurtleneckCoach/Views/SettingsView.swift \
  TurtleneckCoach/Views/SettingsWindowController.swift \
  TurtleneckCoach/Views/OnboardingView.swift \
  TurtleneckCoach/Views/OnboardingPreviewController.swift \
  -o TurtleneckCoach.app/Contents/MacOS/TurtleneckCoach \
  -target arm64-apple-macos14 \
  -framework SwiftUI -framework Vision -framework AVFoundation -framework UserNotifications -framework AppKit -framework Network -framework Charts \
  -parse-as-library -D DEBUG

echo "Signing..."

codesign -s - --entitlements /dev/stdin TurtleneckCoach.app <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "Done! Local DEBUG app ready at ./TurtleneckCoach.app"
echo "Run: open TurtleneckCoach.app"
