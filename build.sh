#!/bin/bash
# Build and sign TurtleneckCoach
set -e

echo "Building TurtleneckCoach..."

# Ensure app bundle structure exists
mkdir -p TurtleneckCoach.app/Contents/MacOS
mkdir -p TurtleneckCoach.app/Contents/Resources

# Copy app icon
cp TurtleneckCoach/Resources/AppIcon.icns TurtleneckCoach.app/Contents/Resources/AppIcon.icns

# Create Info.plist if missing
if [ ! -f TurtleneckCoach.app/Contents/Info.plist ]; then
cat > TurtleneckCoach.app/Contents/Info.plist << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.turtleneck.detector</string>
    <key>CFBundleName</key>
    <string>Turtleneck Coach</string>
    <key>CFBundleExecutable</key>
    <string>TurtleneckCoach</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Turtleneck Coach uses the camera to analyze your posture. Images are processed on-device and never stored.</string>
</dict>
</plist>
INFOPLIST
fi

swiftc \
  TurtleneckCoach/DesignSystem/DesignTokens.swift \
  TurtleneckCoach/Core/CalibrationManager.swift \
  TurtleneckCoach/Core/CameraManager.swift \
  TurtleneckCoach/Core/MediaPipeClient.swift \
  TurtleneckCoach/Core/PostureAnalyzer.swift \
  TurtleneckCoach/Core/PostureClassifier.swift \
  TurtleneckCoach/Core/PostureDataStore.swift \
  TurtleneckCoach/Core/PostureEngine.swift \
  TurtleneckCoach/Core/VisionPoseDetector.swift \
  TurtleneckCoach/Models/CalibrationData.swift \
  TurtleneckCoach/Models/CameraSourceMode.swift \
  TurtleneckCoach/Models/CameraPosition.swift \
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

echo "Done! Run: open TurtleneckCoach.app"
