import UserNotifications
import Foundation

/// Manages macOS native notifications with cooldown.
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

    /// PT Turtle notification messages by severity.
    static func message(for severity: Severity) -> String {
        switch severity {
        case .mild:
            return "Your head is drifting forward. Quick reset: chin back, sit tall."
        case .moderate:
            return "Your neck is doing extra work. Sit back and bring your chin in."
        case .severe:
            return "Time for a break. Stand up, roll your shoulders, stretch your neck."
        case .good:
            return "Looking good. Keep going."
        }
    }

    /// Reset cooldown so next notification sends immediately.
    func resetCooldown() {
        lastNotificationTime = .distantPast
    }
}
