import SwiftUI
import UserNotifications
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var engine: PostureEngine

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @AppStorage(NotificationService.notificationsEnabledKey)
    private var notificationsEnabled = true

    @State private var systemNotificationStatus: UNAuthorizationStatus = .authorized

    @AppStorage(SensitivityMode.storageKey)
    private var sensitivityModeRawValue = SensitivityMode.defaultMode.rawValue

    @AppStorage(NotificationService.notificationFrequencyKey)
    private var notificationFrequencyRawValue = NotificationFrequency.defaultFrequency.rawValue

    @AppStorage(NotificationService.minSeverityKey)
    private var minSeverityRawValue = Severity.correction.rawValue

    @AppStorage(PowerSavingSettings.autoPauseWhenAwayKey)
    private var autoPauseWhenAway = PowerSavingSettings.defaultAutoPauseWhenAway

    @AppStorage(PowerSavingSettings.inactiveTimeoutSecondsKey)
    private var inactiveTimeoutSeconds = PowerSavingSettings.defaultInactiveTimeoutSeconds

    private var sensitivityModeBinding: Binding<SensitivityMode> {
        Binding(
            get: { SensitivityMode(rawValue: sensitivityModeRawValue) ?? .balanced },
            set: { sensitivityModeRawValue = $0.rawValue }
        )
    }

    private var notificationFrequencyBinding: Binding<NotificationFrequency> {
        Binding(
            get: { NotificationFrequency(rawValue: notificationFrequencyRawValue) ?? .normal },
            set: { notificationFrequencyRawValue = $0.rawValue }
        )
    }

    private var minSeverityBinding: Binding<Severity> {
        Binding(
            get: { Severity(rawValue: minSeverityRawValue) ?? .correction },
            set: { minSeverityRawValue = $0.rawValue }
        )
    }

    private var baselineText: String {
        guard let baseline = engine.calibrationData?.neckEarAngle else { return "Not calibrated" }
        return "CVA \(Int(baseline.rounded()))°"
    }

    private var calibrationStatusText: String {
        if engine.isCalibrating {
            return "\(Int(engine.calibrationProgress * 100))% complete"
        }
        return engine.calibrationData == nil ? "No baseline saved" : "Ready"
    }

    private var inactiveTimeoutLabel: String {
        let totalSeconds = Int(inactiveTimeoutSeconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            return "\(totalSeconds)s"
        }
        if seconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
    }

    private var cameraSourceDescription: String {
        let camera = engine.activeCameraDisplayName
        let position = engine.inferredCameraContext == .unknown
            ? "Checking..."
            : engine.inferredCameraContext.displayName
        let framing = engine.inferredFramingState.displayName
        return "Using \(camera). \(position), \(framing)."
    }

    private var manualCameraDescription: String {
        if engine.manualCameraDeviceID.isEmpty {
            return "Select a camera device below."
        }
        let position = engine.inferredCameraContext == .unknown
            ? "Checking..."
            : engine.inferredCameraContext.displayName
        let framing = engine.inferredFramingState.displayName
        return "\(position), \(framing)."
    }

    private var sensitivityDescription: String {
        switch SensitivityMode(rawValue: sensitivityModeRawValue) ?? .balanced {
        case .relaxed: return "Gentler scores. Recommended if you're just starting."
        case .balanced: return "Standard scores for daily monitoring."
        case .strict: return "Tighter scores for those with good posture."
        }
    }

    private var frequencyDescription: String {
        switch NotificationFrequency(rawValue: notificationFrequencyRawValue) ?? .normal {
        case .often: return "Alerts every 30 seconds."
        case .normal: return "Alerts every 2.5 minutes."
        case .rarely: return "Alerts every 5 minutes."
        }
    }

    private var minSeverityDescription: String {
        switch Severity(rawValue: minSeverityRawValue) ?? .correction {
        case .good: return "Notify for any deviation from good posture."
        case .correction: return "Notify when posture needs correction."
        case .bad: return "Notify only for bad posture."
        case .away: return "Notify only when away or very bad posture."
        }
    }

    private let valueColumnWidth: CGFloat = 220
    private let menuWidth: CGFloat = 170

    @ViewBuilder
    private func valueColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            content()
        }
        .frame(width: valueColumnWidth, alignment: .trailing)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker("", selection: $engine.cameraSourceMode) {
                        Text("Auto (Recommended)").tag(CameraSourceMode.auto)
                        Text("Manual").tag(CameraSourceMode.manual)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: menuWidth, alignment: .trailing)
                } label: {
                    VStack(alignment: .leading, spacing: 2) { // DS: one-off (macOS System Settings pattern)
                        Text("Camera Source")
                        Text(cameraSourceDescription)
                            .font(DS.Font.subhead)
                            .foregroundStyle(.secondary)
                    }
                }

                if engine.cameraSourceMode == .manual {
                    LabeledContent {
                        Picker("", selection: $engine.manualCameraDeviceID) {
                            Text("Select Camera").tag("")
                            ForEach(engine.availableCameraDevices) { option in
                                Text(engine.cameraDeviceDisplayName(for: option))
                                    .tag(engine.cameraDeviceID(for: option))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: menuWidth, alignment: .trailing)
                        .disabled(engine.availableCameraDevices.isEmpty)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) { // DS: one-off
                            Text("Camera Device")
                            Text(manualCameraDescription)
                                .font(DS.Font.subhead)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Camera")
            }

            Section {
                LabeledContent("Auto-pause when away") {
                    valueColumn {
                        Toggle("", isOn: $autoPauseWhenAway)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                LabeledContent("Go inactive after") {
                    valueColumn {
                        HStack(spacing: 8) {
                            Slider(
                                value: $inactiveTimeoutSeconds,
                                in: PowerSavingSettings.minInactiveTimeoutSeconds...PowerSavingSettings.maxInactiveTimeoutSeconds,
                                step: 5
                            )
                            .frame(width: 120)

                            Text(inactiveTimeoutLabel)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                }
                .disabled(!autoPauseWhenAway)
            } header: {
                Text("Power Saving")
            } footer: {
                Text("Reduces camera activity when no one is detected to save battery.")
            }

            Section {
                LabeledContent("Open at Login") {
                    valueColumn {
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                    launchAtLogin = newValue
                                } catch {
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            } header: {
                Text("General")
            }

            Section {
                LabeledContent {
                    Picker("", selection: sensitivityModeBinding) {
                        ForEach(SensitivityMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: menuWidth, alignment: .trailing)
                } label: {
                    VStack(alignment: .leading, spacing: 2) { // DS: one-off
                        Text("Sensitivity")
                        Text(sensitivityDescription)
                            .font(DS.Font.subhead)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sensitivity")
            }

            Section {
                if systemNotificationStatus == .denied {
                    LabeledContent("macOS Notifications") {
                        valueColumn {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Denied")
                                    .foregroundColor(.secondary)
                                Button("Open Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                } else if systemNotificationStatus == .notDetermined {
                    LabeledContent("macOS Notifications") {
                        valueColumn {
                            Text("Not requested yet")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                LabeledContent("Enable Notifications") {
                    valueColumn {
                        Toggle("", isOn: $notificationsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                LabeledContent {
                    Picker("", selection: notificationFrequencyBinding) {
                        ForEach(NotificationFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: menuWidth, alignment: .trailing)
                } label: {
                    VStack(alignment: .leading, spacing: 2) { // DS: one-off
                        Text("Frequency")
                        Text(frequencyDescription)
                            .font(DS.Font.subhead)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!notificationsEnabled)

                LabeledContent {
                    Picker("", selection: minSeverityBinding) {
                        ForEach(Severity.allCases, id: \.self) { severity in
                            Text(severity.displayName).tag(severity)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: menuWidth, alignment: .trailing)
                } label: {
                    VStack(alignment: .leading, spacing: 2) { // DS: one-off
                        Text("Minimum Severity")
                        Text(minSeverityDescription)
                            .font(DS.Font.subhead)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!notificationsEnabled)
            } header: {
                Text("Notifications")
            }

            Section {
                LabeledContent("Baseline") {
                    valueColumn {
                        Text(baselineText)
                            .monospacedDigit()
                            .foregroundStyle(engine.calibrationData == nil ? .secondary : .primary)
                    }
                }

                LabeledContent("Status") {
                    valueColumn {
                        Text(calibrationStatusText)
                            .monospacedDigit()
                            .foregroundStyle(engine.isCalibrating ? .secondary : .primary)
                    }
                }

                if engine.isCalibrating {
                    LabeledContent("Progress") {
                        valueColumn {
                            ProgressView(value: engine.calibrationProgress)
                                .frame(width: menuWidth)
                        }
                    }
                }

                LabeledContent("Actions") {
                    HStack(spacing: 8) {
                        Button(engine.calibrationData == nil ? "Start Calibration" : "Recalibrate") {
                            engine.startCalibration()
                        }
                        .disabled(engine.isCalibrating)

                        Button("Reset Baseline", role: .destructive) {
                            engine.resetCalibration()
                        }
                        .disabled(engine.calibrationData == nil && !engine.isCalibrating)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } header: {
                Text("Calibration")
            } footer: {
                Text("Calibration data is stored locally on this Mac.")
            }

            Section {
                LabeledContent("Version") {
                    valueColumn {
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("") {
                    valueColumn {
                        Button("Send Feedback") { openFeedbackEmail() }
                    }
                }

                LabeledContent("") {
                    valueColumn {
                        Button("Export Session Data") { exportSessionData() }
                    }
                }

                LabeledContent("") {
                    valueColumn {
                        Link("Privacy Policy",
                             destination: privacyPolicyURL)
                    }
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding(DS.Space.xl)
        .frame(minWidth: 540, minHeight: 460)
        .onAppear {
            engine.refreshCameraDevices()
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    systemNotificationStatus = settings.authorizationStatus
                }
            }
        }
        .onChange(of: engine.cameraSourceMode) {
            engine.refreshCameraDevices()
        }
    }

    // MARK: - About Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://gist.github.com/ilwonyoon/3e4c3781ab34990acb8af2f5972b687b")!
    }

    private func openFeedbackEmail() {
        let version = appVersion
        let build = buildNumber
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        let today = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        let sessions = engine.dataStore.loadSessions(range: today...todayEnd)
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.duration } / 60.0
        let avgScore = sessions.isEmpty ? 0.0 :
            sessions.reduce(0.0) { $0 + $1.averageScore } / Double(sessions.count)
        let corrections = sessions.reduce(0) { $0 + $1.resetCount }

        let subject = "Turtleneck Coach Feedback v\(version)"
        let body = """
        ---
        App: Turtleneck Coach \(version) (build \(build))
        macOS: \(os)
        Today: \(String(format: "%.0f", totalMinutes))min monitored, avg score \(String(format: "%.0f", avgScore)), \(corrections) corrections
        ---

        (Write your feedback here)

        """

        let mailto = "mailto:ilwonyoon@gmail.com?subject=\(subject)&body=\(body)"
        if let encoded = mailto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportSessionData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        panel.nameFieldStringValue = "turtleneck-coach-sessions-\(dateString).json"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let now = Date()
            let ninetyDaysAgo = now.addingTimeInterval(-90 * 86400)
            let sessions = engine.dataStore.loadSessions(range: ninetyDaysAgo...now)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(sessions) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
