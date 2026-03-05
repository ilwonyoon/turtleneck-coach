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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Posture Dashboard"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame PostureDashboard")
        newWindow.setFrameAutosaveName("PostureDashboard")
        newWindow.minSize = NSSize(width: 500, height: 580)

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
