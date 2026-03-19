import Foundation
import AppKit

final class UsageAnalyticsService {
    static let shared = UsageAnalyticsService()
    static let analyticsEnabledKey = "anonymousUsageAnalyticsEnabled"

    private enum DefaultsKey {
        static let installID = "anonymousUsageAnalytics.installID"
        static let firstInstallTracked = "anonymousUsageAnalytics.firstInstallTracked"
        static let lastDailyActiveDay = "anonymousUsageAnalytics.lastDailyActiveDay"
    }

    private enum InfoKey {
        static let endpointURL = "TurtleneckAnalyticsEndpointURL"
        static let enabledByDefault = "TurtleneckAnalyticsEnabledByDefault"
    }

    private enum EventName: String {
        case firstInstall = "first_install"
        case appOpen = "app_open"
        case dailyActive = "daily_active"
    }

    private struct EventPayload: Encodable {
        let installID: String
        let eventName: String
        let occurredAt: String
        let localDay: String
        let appVersion: String
        let buildNumber: String
        let platform: String
        let osVersion: String

        enum CodingKeys: String, CodingKey {
            case installID = "install_id"
            case eventName = "event_name"
            case occurredAt = "occurred_at"
            case localDay = "local_day"
            case appVersion = "app_version"
            case buildNumber = "build_number"
            case platform
            case osVersion = "os_version"
        }
    }

    private let userDefaults: UserDefaults
    private let bundle: Bundle
    private let session: URLSession
    private var dayChangedObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false

    private init(userDefaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.userDefaults = userDefaults
        self.bundle = bundle

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        stop()
    }

    static func isConfigured(in bundle: Bundle = .main) -> Bool {
        guard let endpointURL = resolvedEndpointURL(in: bundle) else { return false }
        let scheme = endpointURL.scheme?.lowercased()
        return endpointURL.host != nil && (scheme == "https" || scheme == "http")
    }

    func start() {
        registerPreferenceDefaultIfNeeded()

        guard Self.isConfigured(in: bundle) else { return }
        ensureInstallID()

        if !hasStarted {
            hasStarted = true
            registerObservers()
        }

        guard isEnabled else { return }

        trackFirstInstallIfNeeded()
        track(.appOpen)
        trackDailyActiveIfNeeded()
    }

    func stop() {
        if let dayChangedObserver {
            NotificationCenter.default.removeObserver(dayChangedObserver)
            self.dayChangedObserver = nil
        }

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        hasStarted = false
    }

    func handlePreferenceChanged() {
        guard hasStarted, Self.isConfigured(in: bundle), isEnabled else { return }
        trackFirstInstallIfNeeded()
        trackDailyActiveIfNeeded()
    }

    private var isEnabled: Bool {
        if let storedValue = userDefaults.object(forKey: Self.analyticsEnabledKey) as? Bool {
            return storedValue
        }

        return bundle.object(forInfoDictionaryKey: InfoKey.enabledByDefault) as? Bool ?? true
    }

    private var endpointURL: URL? {
        Self.resolvedEndpointURL(in: bundle)
    }

    private func registerPreferenceDefaultIfNeeded() {
        guard userDefaults.object(forKey: Self.analyticsEnabledKey) == nil else { return }
        let defaultValue = bundle.object(forInfoDictionaryKey: InfoKey.enabledByDefault) as? Bool ?? true
        userDefaults.set(defaultValue, forKey: Self.analyticsEnabledKey)
    }

    private func registerObservers() {
        dayChangedObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.trackDailyActiveIfNeeded()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.trackDailyActiveIfNeeded()
        }
    }

    private func ensureInstallID() {
        guard userDefaults.string(forKey: DefaultsKey.installID) == nil else { return }
        userDefaults.set(UUID().uuidString.lowercased(), forKey: DefaultsKey.installID)
    }

    private func trackFirstInstallIfNeeded() {
        guard !userDefaults.bool(forKey: DefaultsKey.firstInstallTracked) else { return }
        userDefaults.set(true, forKey: DefaultsKey.firstInstallTracked)
        track(.firstInstall)
    }

    private func trackDailyActiveIfNeeded() {
        let localDay = Self.localDayString(from: Date())
        guard userDefaults.string(forKey: DefaultsKey.lastDailyActiveDay) != localDay else { return }
        userDefaults.set(localDay, forKey: DefaultsKey.lastDailyActiveDay)
        track(.dailyActive, localDay: localDay)
    }

    private func track(_ eventName: EventName, localDay: String? = nil) {
        guard isEnabled,
              let endpointURL,
              let installID = userDefaults.string(forKey: DefaultsKey.installID)
        else {
            return
        }

        let now = Date()
        let payload = EventPayload(
            installID: installID,
            eventName: eventName.rawValue,
            occurredAt: Self.iso8601UTCString(from: now),
            localDay: localDay ?? Self.localDayString(from: now),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            platform: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            #if DEBUG
            print("Usage analytics encode failed: \(error)")
            #endif
            return
        }

        session.dataTask(with: request) { _, response, error in
            #if DEBUG
            if let error {
                print("Usage analytics request failed: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                print("Usage analytics request failed with status \(httpResponse.statusCode)")
            }
            #endif
        }.resume()
    }

    private static func resolvedEndpointURL(in bundle: Bundle) -> URL? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: InfoKey.endpointURL) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func iso8601UTCString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func localDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
