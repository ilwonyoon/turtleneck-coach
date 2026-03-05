import SwiftUI
import AppKit

/// Opens DashboardView in a standalone NSWindow so it isn't constrained
/// by the MenuBarExtra popover size and doesn't dismiss the popover on click.
@MainActor
final class DashboardWindowController {
    static let shared = DashboardWindowController()

    private var window: NSWindow?

    func show(engine: PostureEngine) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dashboard = DashboardView(engine: engine)
        let hostingView = NSHostingView(rootView: dashboard)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Posture Dashboard"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("PostureDashboard")
        newWindow.minSize = NSSize(width: 600, height: 480)

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
