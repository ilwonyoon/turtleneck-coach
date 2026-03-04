import UserNotifications
import Foundation

enum NotificationFrequency: String, CaseIterable {
    case often
    case normal
    case rarely

    static let storageKey = "notificationFrequency"
    static let defaultFrequency: NotificationFrequency = .normal

    var displayName: String {
        switch self {
        case .often: return "Often"
        case .normal: return "Normal"
        case .rarely: return "Rarely"
        }
    }

    var cooldownSeconds: TimeInterval {
        switch self {
        case .often: return 30
        case .normal: return 150
        case .rarely: return 300
        }
    }
}

/// Manages macOS native notifications with cooldown.
final class NotificationService {
    static let notificationsEnabledKey = "notificationsEnabled"
    static let notificationFrequencyKey = NotificationFrequency.storageKey
    static let minSeverityKey = "minSeverity"

    private let userDefaults: UserDefaults
    private var notificationsEnabled: Bool = true
    private var notificationFrequency: NotificationFrequency = .normal
    private var minSeverity: Severity = .correction
    private var lastNotificationTime: Date = .distantPast

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            Self.notificationsEnabledKey: true,
            Self.notificationFrequencyKey: NotificationFrequency.defaultFrequency.rawValue,
            Self.minSeverityKey: Severity.correction.rawValue
        ])
        loadSettingsFromUserDefaults()
    }

    private func loadSettingsFromUserDefaults() {
        notificationsEnabled = userDefaults.bool(forKey: Self.notificationsEnabledKey)
        let frequencyRawValue = userDefaults.string(forKey: Self.notificationFrequencyKey) ?? ""
        notificationFrequency = NotificationFrequency(rawValue: frequencyRawValue) ?? .normal

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
        guard now.timeIntervalSince(lastNotificationTime) >= notificationFrequency.cooldownSeconds else {
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
