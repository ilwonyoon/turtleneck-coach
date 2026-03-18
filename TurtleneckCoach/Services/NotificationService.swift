import AppKit
import Foundation
import UserNotifications
import os.log

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

struct NotificationSoundOption: Identifiable, Hashable {
    static let storageKey = "notificationSound"
    static let legacySystemDefaultID = "__default__"
    static let legacyNoneID = "__none__"
    static let offID = "__off__"
    static let preferredDefaultID = "Glass"
    static let offOption = NotificationSoundOption(id: offID, displayName: "Off")

    let id: String
    let displayName: String

    private static let cachedSystemOptions: [NotificationSoundOption] = loadSystemSoundOptions()

    static var allOptions: [NotificationSoundOption] {
        [offOption] + cachedSystemOptions
    }

    static func normalizedID(_ storedValue: String?) -> String {
        let trimmedValue = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedValue.isEmpty else {
            return defaultSoundID
        }

        switch trimmedValue {
        case legacyNoneID, offID:
            return offID
        case legacySystemDefaultID:
            return defaultSoundID
        default:
            return allOptions.contains(where: { $0.id == trimmedValue }) ? trimmedValue : defaultSoundID
        }
    }

    static func option(for storedValue: String?) -> NotificationSoundOption {
        let normalizedValue = normalizedID(storedValue)
        return allOptions.first(where: { $0.id == normalizedValue }) ?? defaultOption
    }

    static func playbackSoundName(for storedValue: String?) -> String? {
        let normalizedValue = normalizedID(storedValue)
        guard normalizedValue != offID else {
            return nil
        }
        return normalizedValue
    }

    static var defaultOption: NotificationSoundOption {
        option(for: defaultSoundID)
    }

    private static var defaultSoundID: String {
        if cachedSystemOptions.contains(where: { $0.id == preferredDefaultID }) {
            return preferredDefaultID
        }

        return cachedSystemOptions.first?.id ?? offID
    }

    private static func loadSystemSoundOptions() -> [NotificationSoundOption] {
        let systemSoundDirectory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        let soundExtensions = Set(["aiff", "wav", "caf"])

        guard let soundURLs = try? FileManager.default.contentsOfDirectory(
            at: systemSoundDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return soundURLs
            .filter { soundExtensions.contains($0.pathExtension.lowercased()) }
            .map { NotificationSoundOption(id: $0.deletingPathExtension().lastPathComponent, displayName: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

/// Manages macOS native notifications with cooldown.
final class NotificationService: NSObject {
    private let logger = Logger(subsystem: "com.turtleneck.detector", category: "Notifications")
    static let notificationsEnabledKey = "notificationsEnabled"
    static let notificationFrequencyKey = NotificationFrequency.storageKey
    static let minSeverityKey = "minSeverity"
    static let notificationSoundKey = NotificationSoundOption.storageKey
    static let notificationSoundEnabledKey = "notificationSoundEnabled" // legacy migration only

    private var userDefaults: UserDefaults = .standard
    private var notificationsEnabled: Bool = true
    private var notificationFrequency: NotificationFrequency = .normal
    private var minSeverity: Severity = .correction
    private var notificationSoundID: String = NotificationSoundOption.defaultOption.id
    private var lastNotificationTime: Date = .distantPast
    private var activeSound: NSSound?
    private static var previewPlayer: NSSound?
    private static var previewSoundCache: [String: NSSound] = [:]
    private static var pendingPreviewWorkItem: DispatchWorkItem?

    init(userDefaults: UserDefaults = .standard) {
        super.init()
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            Self.notificationsEnabledKey: true,
            Self.notificationFrequencyKey: NotificationFrequency.defaultFrequency.rawValue,
            Self.minSeverityKey: Severity.correction.rawValue,
            Self.notificationSoundKey: NotificationSoundOption.defaultOption.id
        ])
        Self.migrateLegacySoundPreference(in: userDefaults)
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

        notificationSoundID = Self.migrateLegacySoundPreference(in: userDefaults)
    }

    /// Request notification permission.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { [weak self] granted, error in
            if let error {
                self?.logger.log("Notification permission error: \(error.localizedDescription, privacy: .public)")
            }
            if !granted {
                self?.logger.log("Notification permission denied by user")
            }
        }
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
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "posture-alert-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )

        let playbackSoundName = NotificationSoundOption.playbackSoundName(for: notificationSoundID)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.log("Notification scheduling error: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let playbackSoundName else {
                return
            }

            DispatchQueue.main.async {
                self?.playSound(named: playbackSoundName)
            }
        }
        lastNotificationTime = now
        return true
    }

    /// Turtleneck Coach notification messages by severity.
    static func message(for severity: Severity) -> (title: String, body: String) {
        switch severity {
        case .correction:
            return ("⚠️ Turtleneck Coach", "Head's drifting. Tuck your chin.")
        case .bad:
            return ("🔴 Turtleneck Coach", "Posture's gone. Sit up, reset.")
        case .away:
            return ("Turtleneck Coach", "")
        case .good:
            return ("Turtleneck Coach", "")
        }
    }

    /// Reset cooldown so next notification sends immediately.
    func resetCooldown() {
        lastNotificationTime = .distantPast
    }

    @discardableResult
    static func migrateLegacySoundPreference(in userDefaults: UserDefaults = .standard) -> String {
        if userDefaults.object(forKey: notificationSoundEnabledKey) != nil {
            let normalizedSoundID: String
            if userDefaults.bool(forKey: notificationSoundEnabledKey) {
                normalizedSoundID = NotificationSoundOption.normalizedID(
                    userDefaults.string(forKey: notificationSoundKey)
                )
            } else {
                normalizedSoundID = NotificationSoundOption.offID
            }

            userDefaults.set(normalizedSoundID, forKey: notificationSoundKey)
            userDefaults.removeObject(forKey: notificationSoundEnabledKey)
            return normalizedSoundID
        }

        let normalizedSoundID = NotificationSoundOption.normalizedID(
            userDefaults.string(forKey: notificationSoundKey)
        )
        if normalizedSoundID != userDefaults.string(forKey: notificationSoundKey) {
            userDefaults.set(normalizedSoundID, forKey: notificationSoundKey)
        }
        return normalizedSoundID
    }

    static func previewSound(soundID: String) {
        pendingPreviewWorkItem?.cancel()
        pendingPreviewWorkItem = nil

        guard let soundName = NotificationSoundOption.playbackSoundName(for: soundID) else {
            previewPlayer?.stop()
            previewPlayer = nil
            return
        }

        let workItem = DispatchWorkItem {
            guard let sound = cachedPreviewSound(named: soundName) else {
                return
            }

            previewPlayer?.stop()
            previewPlayer = sound
            _ = sound.play()
        }

        pendingPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private static func cachedPreviewSound(named name: String) -> NSSound? {
        if let cachedSound = previewSoundCache[name] {
            return cachedSound
        }

        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return nil
        }

        previewSoundCache[name] = sound
        return sound
    }

    private func playSound(named name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            logger.log("Notification sound not found: \(name, privacy: .public)")
            return
        }

        activeSound?.stop()
        activeSound = sound

        if !sound.play() {
            logger.log("Notification sound failed to play: \(name, privacy: .public)")
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
