import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(engine: PostureEngine) {
        if let existing = window {
            existing.contentView = NSHostingView(rootView: SettingsView(engine: engine))
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = NSHostingView(rootView: SettingsView(engine: engine))

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Settings"
        newWindow.contentView = contentView
        newWindow.center()
        newWindow.minSize = NSSize(width: 520, height: 440)
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("PTTurtleSettings")
        newWindow.toolbarStyle = .preference

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
