import SwiftUI
import UserNotifications

@main
struct TurtleneckCoachApp: App {
    @StateObject private var engine = PostureEngine()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            Group {
                if hasCompletedOnboarding {
                    MenuBarView(engine: engine)
                        .frame(width: 340, height: 520)
                } else {
                    OnboardingView(engine: engine)
                        .frame(width: 340)
                }
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Request camera permission.
    /// Returns true when camera access is granted.
    static func requestAllPermissions() async -> Bool {
        await CameraManager.requestPermission()
    }

    /// Request notifications only if the app has never asked before.
    static func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
