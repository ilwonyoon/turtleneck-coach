import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: PostureEngine

    @AppStorage(NotificationService.notificationsEnabledKey)
    private var notificationsEnabled = true

    @AppStorage(NotificationService.cooldownSecondsKey)
    private var cooldownSeconds = 60.0

    @AppStorage(NotificationService.minSeverityKey)
    private var minSeverityRawValue = Severity.bad.rawValue

    private var minSeverityBinding: Binding<Severity> {
        Binding(
            get: { Severity(rawValue: minSeverityRawValue) ?? .bad },
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
    private let stepperValueWidth: CGFloat = 72

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
                LabeledContent("Enable Notifications") {
                    valueColumn {
                        Toggle("", isOn: $notificationsEnabled)
                            .labelsHidden()
                    }
                }

                LabeledContent("Cooldown") {
                    valueColumn {
                        HStack(spacing: 8) {
                            Text("\(Int(cooldownSeconds)) sec")
                                .monospacedDigit()
                                .frame(width: stepperValueWidth, alignment: .trailing)

                            Stepper("", value: $cooldownSeconds, in: 30...300, step: 30)
                                .labelsHidden()
                        }
                    }
                }
                .disabled(!notificationsEnabled)

                LabeledContent("Minimum Severity") {
                    valueColumn {
                        Picker("", selection: minSeverityBinding) {
                            Text("Correction").tag(Severity.correction)
                            Text("Bad Posture").tag(Severity.bad)
                            Text("Away / Break").tag(Severity.away)
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
                Text("Alerts are delivered through macOS Notification Center.")
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
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
    }
}
