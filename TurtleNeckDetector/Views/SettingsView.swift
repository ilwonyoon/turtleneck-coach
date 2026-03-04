import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: PostureEngine

    @AppStorage(NotificationService.notificationsEnabledKey)
    private var notificationsEnabled = true

    @AppStorage(SensitivityMode.storageKey)
    private var sensitivityModeRawValue = SensitivityMode.defaultMode.rawValue

    @AppStorage(NotificationService.notificationFrequencyKey)
    private var notificationFrequencyRawValue = NotificationFrequency.defaultFrequency.rawValue

    @AppStorage(NotificationService.minSeverityKey)
    private var minSeverityRawValue = Severity.correction.rawValue

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
                LabeledContent("Camera Position") {
                    valueColumn {
                        Picker("", selection: $engine.cameraPosition) {
                            ForEach(CameraPosition.allCases, id: \.self) { position in
                                Text(position.rawValue.capitalized).tag(position)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: menuWidth, alignment: .trailing)
                    }
                }
            } header: {
                Text("Camera")
            } footer: {
                Text("Choose where your camera is placed for posture analysis.")
            }

            Section {
                LabeledContent("Sensitivity") {
                    valueColumn {
                        Picker("", selection: sensitivityModeBinding) {
                            ForEach(SensitivityMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: menuWidth, alignment: .trailing)
                    }
                }
            } header: {
                Text("Sensitivity")
            } footer: {
                Text("How strict the posture scoring is. Relaxed suits casual use; Strict is for focused work sessions.")
            }

            Section {
                LabeledContent("Enable Notifications") {
                    valueColumn {
                        Toggle("", isOn: $notificationsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                LabeledContent("Frequency") {
                    valueColumn {
                        Picker("", selection: notificationFrequencyBinding) {
                            ForEach(NotificationFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: menuWidth, alignment: .trailing)
                    }
                }
                .disabled(!notificationsEnabled)

                LabeledContent("Minimum Severity") {
                    valueColumn {
                        Picker("", selection: minSeverityBinding) {
                            ForEach(Severity.allCases, id: \.self) { severity in
                                Text(severity.displayName).tag(severity)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: menuWidth, alignment: .trailing)
                    }
                }
                .disabled(!notificationsEnabled)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Often: every 30s · Normal: every 2.5min · Rarely: every 5min. Delivered via macOS Notification Center.")
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
        }
        .formStyle(.grouped)
        .padding(DS.Space.xxl)
        .frame(minWidth: 540, minHeight: 460)
    }
}
