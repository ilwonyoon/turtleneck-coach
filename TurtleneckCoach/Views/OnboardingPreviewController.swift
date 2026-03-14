import SwiftUI
import AppKit

#if DEBUG
@MainActor
final class OnboardingPreviewController {
    static let shared = OnboardingPreviewController()

    private var window: NSWindow?

    private init() {}

    func show(engine: PostureEngine) {
        if let existing = window {
            existing.contentView = NSHostingView(rootView: OnboardingView(engine: engine))
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = NSHostingView(rootView: OnboardingView(engine: engine))

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Onboarding Preview"
        newWindow.contentView = contentView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("PTTurtleOnboardingPreview")

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
#endif
