# P0-1: Onboarding Experience

## Problem

First-time users see the menu bar popover cold — no explanation of what the app does, how scoring works, or what to expect. Permissions are requested without context.

## Target Flow

```
Welcome screen → "Get Started" (requests permissions) → Camera + Calibration → Score Zones → monitoring
```

Returning users skip onboarding entirely via persisted flag.

## Current Flow (what to change)

**`TurtleneckCoachApp.swift`** currently:
1. Requests permissions in `.task` block before showing UI
2. Shows a spinner while waiting
3. Shows `MenuBarView` once permissions resolve

```swift
// Current structure (lines 6-35)
@State private var permissionsReady = false

var body: some Scene {
    MenuBarExtra {
        Group {
            if permissionsReady {
                MenuBarView(engine: engine).frame(width: 340, height: 640)
            } else {
                VStack { ProgressView(); Text("Requesting permissions...") }
            }
        }
        .task { await requestAllPermissions(); permissionsReady = true }
    }
}
```

## Implementation

### 1. Modify `TurtleneckCoachApp.swift`

- Replace `@State private var permissionsReady = false` with `@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false`
- Remove the `.task { await requestAllPermissions() }` block
- Replace body:

```swift
var body: some Scene {
    MenuBarExtra {
        if hasCompletedOnboarding {
            MenuBarView(engine: engine)
                .frame(width: 340, height: 640)
        } else {
            OnboardingView(engine: engine, hasCompletedOnboarding: $hasCompletedOnboarding)
                .frame(width: 340, height: 640)
        }
    } label: {
        menuBarLabel
    }
    .menuBarExtraStyle(.window)
}
```

- Keep `requestAllPermissions()` function — OnboardingView will call the same logic inline.

### 2. Create `TurtleneckCoach/Views/OnboardingView.swift` (NEW)

Three-step view with `@State private var step = 0`.

```swift
import SwiftUI
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var engine: PostureEngine
    @Binding var hasCompletedOnboarding: Bool
    @State private var step = 0
    @State private var cameraError = false

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0: welcomeStep
            case 1: calibrateStep
            default: scoreZonesStep
            }
        }
    }
}
```

#### Step 0 — Welcome

```swift
private var welcomeStep: some View {
    VStack(spacing: 20) {
        Spacer()
        Image(systemName: "tortoise.fill")
            .font(.system(size: 56))
            .foregroundStyle(.teal)
        Text("Turtleneck Coach")
            .font(.title3.weight(.semibold))
        Text("Monitors your posture while you work.\nNo images are stored.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        Spacer()

        if cameraError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Camera access required. Enable in System Settings > Privacy > Camera.")
                    .font(.caption)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        Button {
            Task {
                // Request permissions
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])

                if granted {
                    step = 1
                    engine.startMonitoring() // starts camera + auto-calibration
                } else {
                    cameraError = true
                }
            }
        } label: {
            Text("Get Started")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }
    .padding(16)
}
```

#### Step 1 — Calibrate

```swift
private var calibrateStep: some View {
    VStack(spacing: 16) {
        Text("Sit up straight")
            .font(.title3.weight(.semibold))
        Text("Look straight ahead in your usual setup and hold still.")
            .font(.subheadline)
            .foregroundColor(.secondary)

        CameraPreviewView(
            frame: engine.currentFrame,
            joints: engine.currentJoints
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(.separatorColor), lineWidth: 1)
        )

        if engine.isCalibrating {
            CalibrationView(
                progress: engine.calibrationProgress,
                message: engine.calibrationMessage
            )
        }

        // Retry button if calibration failed
        if !engine.isCalibrating && engine.calibrationData == nil {
            Button("Retry Calibration") {
                engine.startCalibration()
            }
            .buttonStyle(.bordered)
        }
    }
    .padding(16)
    .onChange(of: engine.isCalibrating) { _, isCalibrating in
        if !isCalibrating && engine.calibrationData != nil {
            withAnimation(.easeInOut(duration: 0.3)) { step = 2 }
        }
    }
}
```

#### Step 2 — Score Zones

```swift
private var scoreZonesStep: some View {
    VStack(spacing: 20) {
        Text("Your Score Zones")
            .font(.title3.weight(.semibold))

        VStack(spacing: 12) {
            scoreZoneRow(color: .green, label: "Great",
                         description: "Good posture. Keep it up.")
            scoreZoneRow(color: .yellow, label: "Adjust",
                         description: "Head is drifting forward.")
            scoreZoneRow(color: .orange, label: "Reset",
                         description: "Time to sit back and reset.")
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        Text("You'll get a gentle reminder if bad posture is sustained.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

        Spacer()

        Button {
            hasCompletedOnboarding = true
        } label: {
            Text("Start Monitoring")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }
    .padding(16)
}

private func scoreZoneRow(color: Color, label: String, description: String) -> some View {
    HStack(spacing: 10) {
        Circle().fill(color).frame(width: 10, height: 10)
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline.weight(.medium))
            Text(description).font(.caption).foregroundColor(.secondary)
        }
        Spacer()
    }
}
```

### 3. Update `build.sh`

Add to the swiftc file list (after `MenuBarView.swift`):
```
TurtleneckCoach/Views/OnboardingView.swift \
```

## Design Patterns (MUST match existing app)

| Element | Pattern |
|---------|---------|
| Backgrounds | `.regularMaterial`, `.thickMaterial` |
| Corners | `RoundedRectangle(cornerRadius: 8)` cards, `12` for larger containers |
| Padding | 16px horizontal on main container |
| Headers | `.title3.weight(.semibold)` |
| Body text | `.subheadline.weight(.medium)` or `.subheadline` |
| Secondary text | `.caption` with `.foregroundColor(.secondary)` |
| Primary buttons | `.buttonStyle(.borderedProminent)` |
| Secondary buttons | `.buttonStyle(.bordered)` |
| Icons | SF Symbols |

## Files Changed

| File | Action |
|------|--------|
| `TurtleneckCoach/TurtleneckCoachApp.swift` | Modify |
| `TurtleneckCoach/Views/OnboardingView.swift` | **New file** |
| `build.sh` | Add new file to compile list |

## Verification

```bash
# Build
./build.sh

# Reset onboarding to test
defaults delete com.turtleneck.detector hasCompletedOnboarding

# OR if using the other bundle ID:
defaults delete com.ilwonyoon.TurtleneckCoach hasCompletedOnboarding

# Launch
open TurtleneckCoach.app
```

- First launch: Welcome → Get Started → permissions dialog → calibration → score zones → monitoring
- Second launch: skips directly to MenuBarView
- Camera denied: shows error banner on welcome screen
