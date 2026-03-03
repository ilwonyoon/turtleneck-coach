import UserNotifications
import Foundation

/// Manages macOS native notifications with cooldown.
/// Port of Python Notifier from notifier.py.
final class NotificationService {
    private let cooldownSeconds: TimeInterval
    private var lastNotificationTime: Date = .distantPast

    init(cooldownSeconds: TimeInterval = 60.0) {
        self.cooldownSeconds = cooldownSeconds
    }

    /// Request notification permission.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    /// Send a notification if cooldown has elapsed. Returns true if sent.
    @discardableResult
    func notify(title: String, message: String, severity: Severity) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationTime) >= cooldownSeconds else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "posture-alert-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
        lastNotificationTime = now
        return true
    }

    /// Severity-specific notification messages (from web_app.py).
    static func message(for severity: Severity) -> String {
        switch severity {
        case .mild:
            return "Mild forward head posture detected."
        case .moderate:
            return "Moderate forward head posture. Sit up straight!"
        case .severe:
            return "Severe forward head posture! Take a break and stretch."
        case .good:
            return "Good posture!"
        }
    }

    /// Reset cooldown so next notification sends immediately.
    func resetCooldown() {
        lastNotificationTime = .distantPast
    }
}
