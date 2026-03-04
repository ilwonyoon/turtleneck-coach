import SwiftUI
import AVFoundation
import UserNotifications

@main
struct TurtleNeckDetectorApp: App {
    @StateObject private var engine = PostureEngine()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            Group {
                if hasCompletedOnboarding {
                    MenuBarView(engine: engine)
                        .frame(width: 340, height: 640)
                } else {
                    OnboardingView(engine: engine)
                        .frame(width: 340, height: 640)
                }
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Request camera + notification permissions.
    /// Returns true when camera access is granted.
    static func requestAllPermissions() async -> Bool {
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return cameraGranted
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "tortoise.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(engine.menuBarIconColor)
            if engine.isMonitoring {
                Text(engine.menuBarStatusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(engine.menuBarIconColor)
            }
        }
    }
}
