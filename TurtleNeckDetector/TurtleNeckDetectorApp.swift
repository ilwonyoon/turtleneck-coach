import SwiftUI

@main
struct TurtleNeckDetectorApp: App {
    @StateObject private var engine = PostureEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
                .frame(width: 340, height: 640)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
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
