import SwiftUI
import AppKit

/// Manages the onboarding window as a standalone NSWindow.
/// Unlike a popover, this window stays open when system dialogs
/// (camera permission, notification permission) steal focus.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<OnboardingView>?

    private static let windowSize = NSSize(width: 640, height: 640)

    private init() {}

    func show(engine: PostureEngine) {
        let size = Self.windowSize

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: OnboardingView(engine: engine))
        controller.sizingOptions = []
        controller.preferredContentSize = size

        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Turtleneck Coach"
        newWindow.contentViewController = controller
        newWindow.setContentSize(size)
        newWindow.contentMinSize = size
        newWindow.contentMaxSize = size
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        self.hostingController = controller
    }

    var isShowing: Bool {
        window?.isVisible == true
    }

    func close() {
        window?.close()
        window = nil
        hostingController = nil
    }
}
