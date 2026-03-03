import SwiftUI
import AVFoundation
import UserNotifications

@main
struct TurtleNeckDetectorApp: App {
    @StateObject private var engine = PostureEngine()
    /// Tracks whether all permissions have been resolved (granted or denied).
    @State private var permissionsReady = false

    var body: some Scene {
        MenuBarExtra {
            Group {
                if permissionsReady {
                    MenuBarView(engine: engine)
                        .frame(width: 340, height: 640)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Requesting permissions...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 340, height: 120)
                }
            }
            .task {
                await requestAllPermissions()
                permissionsReady = true
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Request camera + notification permissions upfront before showing UI.
    /// Once resolved (granted or denied), the popover content appears.
    /// Subsequent launches skip the dialog since macOS remembers the choice.
    private func requestAllPermissions() async {
        // Camera permission — only shows dialog if .notDetermined
        _ = await AVCaptureDevice.requestAccess(for: .video)
        // Notification permission — only shows dialog if not yet decided
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "tortoise.fill")
            if engine.isMonitoring && engine.bodyDetected {
                Text(engine.menuBarStatusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(menuBarTextColor)
            }
        }
    }

    private var menuBarTextColor: Color {
        switch engine.menuBarSeverity {
        case .good: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }
}
