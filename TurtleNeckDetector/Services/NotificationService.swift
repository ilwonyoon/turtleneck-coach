import UserNotifications
import Foundation

/// Manages macOS native notifications with cooldown.
final class NotificationService {
    static let notificationsEnabledKey = "notificationsEnabled"
    static let cooldownSecondsKey = "cooldownSeconds"
    static let minSeverityKey = "minSeverity"

    private let userDefaults: UserDefaults
    private var notificationsEnabled: Bool = true
    private var cooldownSeconds: Double = 60
    private var minSeverity: Severity = .bad
    private var lastNotificationTime: Date = .distantPast

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            Self.notificationsEnabledKey: true,
            Self.cooldownSecondsKey: 60.0,
            Self.minSeverityKey: Severity.bad.rawValue
        ])
        loadSettingsFromUserDefaults()
    }

    private func loadSettingsFromUserDefaults() {
        notificationsEnabled = userDefaults.bool(forKey: Self.notificationsEnabledKey)
        cooldownSeconds = userDefaults.double(forKey: Self.cooldownSecondsKey)

        if let rawValue = userDefaults.string(forKey: Self.minSeverityKey),
           let savedSeverity = Severity(rawValue: rawValue) {
            minSeverity = savedSeverity
        } else {
            minSeverity = .bad
        }
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
        // Pull latest runtime settings without requiring engine/service re-creation.
        loadSettingsFromUserDefaults()

        guard notificationsEnabled else {
            return false
        }

        guard severity >= minSeverity else {
            return false
        }

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
        case .correction:
            return "Quick check: your head is drifting forward. Chin back and sit tall."
        case .bad:
            return "Posture reset time: sit back, open your chest, and bring your chin in."
        case .away:
            return "Need a break? Stand up, move a bit, then come back and reset."
        case .good:
            return "Looking good. Keep going."
        }
    }

    /// Reset cooldown so next notification sends immediately.
    func resetCooldown() {
        lastNotificationTime = .distantPast
    }
}
