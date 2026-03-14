import SwiftUI
import AppKit

#if DEBUG
@MainActor
final class OnboardingPreviewController {
    static let shared = OnboardingPreviewController()
    private init() {}

    func show(engine: PostureEngine) {
        // Reuse the production onboarding window for debug preview
        OnboardingWindowController.shared.show(engine: engine)
    }
}
#endif
