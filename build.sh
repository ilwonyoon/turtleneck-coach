#!/bin/bash
# Build and sign TurtleNeckDetector
set -e

echo "Building TurtleNeckDetector..."

# Ensure app bundle structure exists
mkdir -p TurtleNeckDetector.app/Contents/MacOS

# Create Info.plist if missing
if [ ! -f TurtleNeckDetector.app/Contents/Info.plist ]; then
cat > TurtleNeckDetector.app/Contents/Info.plist << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ilwonyoon.TurtleNeckDetector</string>
    <key>CFBundleName</key>
    <string>TurtleNeckDetector</string>
    <key>CFBundleExecutable</key>
    <string>TurtleNeckDetector</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>TurtleNeckDetector needs camera access to monitor your posture.</string>
</dict>
</plist>
INFOPLIST
fi

swiftc \
  TurtleNeckDetector/Core/CalibrationManager.swift \
  TurtleNeckDetector/Core/CameraManager.swift \
  TurtleNeckDetector/Core/MediaPipeClient.swift \
  TurtleNeckDetector/Core/PostureAnalyzer.swift \
  TurtleNeckDetector/Core/PostureEngine.swift \
  TurtleNeckDetector/Core/VisionPoseDetector.swift \
  TurtleNeckDetector/Models/CalibrationData.swift \
  TurtleNeckDetector/Models/CameraPosition.swift \
  TurtleNeckDetector/Models/PostureMetrics.swift \
  TurtleNeckDetector/Models/PostureState.swift \
  TurtleNeckDetector/Services/FeedbackEngine.swift \
  TurtleNeckDetector/Services/NotificationService.swift \
  TurtleNeckDetector/TurtleNeckDetectorApp.swift \
  TurtleNeckDetector/Views/CalibrationView.swift \
  TurtleNeckDetector/Views/CameraPreviewView.swift \
  TurtleNeckDetector/Views/MenuBarView.swift \
  TurtleNeckDetector/Views/PostureScoreView.swift \
  TurtleNeckDetector/Views/SettingsView.swift \
  -o TurtleNeckDetector.app/Contents/MacOS/TurtleNeckDetector \
  -target arm64-apple-macos14 \
  -framework SwiftUI -framework Vision -framework AVFoundation -framework UserNotifications -framework AppKit -framework Network \
  -parse-as-library

echo "Signing..."

codesign -s - --entitlements /dev/stdin TurtleNeckDetector.app <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "Done! Run: open TurtleNeckDetector.app"
