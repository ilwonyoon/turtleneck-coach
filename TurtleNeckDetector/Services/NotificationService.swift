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
    private var minSeverity: Severity = .correction
    private var lastNotificationTime: Date = .distantPast

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            Self.notificationsEnabledKey: true,
            Self.cooldownSecondsKey: 60.0,
            Self.minSeverityKey: Severity.correction.rawValue
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
            minSeverity = .correction
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

        guard severity != .good, severity != .away else {
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
            return "Head's drifting. Tuck your chin."
        case .bad:
            return "Posture's gone. Sit up, reset."
        case .away:
            return ""
        case .good:
            return ""
        }
    }

    /// Reset cooldown so next notification sends immediately.
    func resetCooldown() {
        lastNotificationTime = .distantPast
    }
}
