import SwiftUI

/// Main popover content shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var engine: PostureEngine
    @State private var showSettings = false
    @State private var refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Error banner
                    if let error = engine.lastError {
                        errorBanner(error)
                    }

                    // Camera preview with skeleton
                    if engine.isMonitoring {
                        ZStack {
                            CameraPreviewView(
                                frame: engine.currentFrame,
                                joints: engine.currentJoints,
                                severity: engine.postureState.severity
                            )
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(cameraBorderColor, lineWidth: cameraBorderWidth)
                            )
                            .overlay(cvaOverlay, alignment: .topTrailing)

                            // Body detection status
                            if engine.currentFrame != nil && !engine.bodyDetected {
                                VStack {
                                    Spacer()
                                    Text("No body detected")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.red.opacity(0.7))
                                        .clipShape(Capsule())
                                        .padding(.bottom, 8)
                                }
                                .frame(height: 200)
                            }
                        }
                    }

                    // Calibration overlay
                    if engine.isCalibrating {
                        CalibrationView(
                            progress: engine.calibrationProgress,
                            message: engine.calibrationMessage,
                            success: nil
                        )
                    } else if let success = engine.calibrationSuccess {
                        CalibrationView(
                            progress: 1.0,
                            message: engine.calibrationMessage,
                            success: success
                        )
                        .onTapGesture {
                            engine.calibrationSuccess = nil
                        }
                    }

                    // Score gauge (when monitoring and body/face detected)
                    if engine.isMonitoring && !engine.isCalibrating && engine.bodyDetected {
                        PostureScoreView(
                            score: engine.postureScore,
                            emoji: engine.postureEmoji
                        )
                        .animation(.easeInOut(duration: 0.8), value: engine.postureScore)
                        .padding(.horizontal, 4)
                    }

                    // Status card
                    statusCard

                    // Badges
                    badgesRow

                    // Deviation meter
                    if engine.calibrationData != nil && engine.isMonitoring {
                        deviationMeter
                    }

                    // Controls
                    controlButtons
                }
                .padding(16)
            }

            Divider()

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .onReceive(refreshTimer) { _ in
            engine.objectWillChange.send()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Turtle Neck Detector")
                    .font(.headline)
                Text("Posture monitoring")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings) {
                SettingsView(engine: engine)
                    .frame(width: 260)
            }
        }
    }

    // MARK: - Camera Overlay

    private var cvaOverlay: some View {
        Group {
            if engine.calibrationData != nil {
                Text("CVA ~\(Int(engine.postureState.currentCVA))\u{00B0}")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }

    private var cameraBorderColor: Color {
        guard engine.calibrationData != nil else { return Color.gray.opacity(0.3) }
        switch engine.postureState.severity {
        case .good: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }

    private var cameraBorderWidth: CGFloat {
        guard engine.calibrationData != nil else { return 1 }
        switch engine.postureState.severity {
        case .good: return 1
        case .mild: return 2
        case .moderate, .severe: return 3
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusMainText)
                    .font(.subheadline.weight(.medium))
                Text(statusSubText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(statusCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statusDotColor: Color {
        guard engine.isMonitoring, engine.calibrationData != nil else { return .gray }
        switch engine.postureState.severity {
        case .good: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }

    private var statusMainText: String {
        guard engine.isMonitoring else { return "Monitoring paused" }
        guard engine.calibrationData != nil else { return "Calibrate to start" }
        if engine.isCalibrating { return "Calibrating..." }

        switch engine.postureState.severity {
        case .good:
            let msg = FeedbackEngine.goodMessage(forDuration: engine.goodPostureDuration)
            return msg.main
        case .mild:
            return "Mild forward head posture"
        case .moderate:
            return "Moderate forward head posture"
        case .severe:
            return "Severe forward head posture"
        }
    }

    private var statusSubText: String {
        guard engine.isMonitoring else { return "Press Start to begin" }
        guard engine.calibrationData != nil else { return "Sit in your best posture, then calibrate" }
        if engine.isCalibrating { return "Hold your correct posture" }

        switch engine.postureState.severity {
        case .good:
            let msg = FeedbackEngine.goodMessage(forDuration: engine.goodPostureDuration)
            return msg.sub
        case .mild, .moderate, .severe:
            return FeedbackEngine.severityTip(for: engine.postureState.severity)
        }
    }

    private var statusCardBackground: some ShapeStyle {
        guard engine.isMonitoring, engine.calibrationData != nil else {
            return AnyShapeStyle(Color.gray.opacity(0.08))
        }
        switch engine.postureState.severity {
        case .good: return AnyShapeStyle(Color.green.opacity(0.08))
        case .mild: return AnyShapeStyle(Color.yellow.opacity(0.08))
        case .moderate: return AnyShapeStyle(Color.orange.opacity(0.08))
        case .severe: return AnyShapeStyle(Color.red.opacity(0.1))
        }
    }

    // MARK: - Badges

    private var badgesRow: some View {
        HStack(spacing: 6) {
            badge(engine.cameraPosition.rawValue.capitalized, color: .blue, icon: "camera")

            if engine.postureState.usingFallback {
                badge("Eye Mode", color: .yellow, icon: "eye")
            }

            if engine.isMonitoring, engine.calibrationData != nil,
               engine.postureState.severity != .good {
                badge(engine.postureState.severity.rawValue.uppercased(), color: severityBadgeColor)
            }

            if engine.goodPostureDuration >= 30 {
                badge(FeedbackEngine.formatTime(engine.goodPostureDuration) + " streak", color: .green, icon: "flame")
            }

            Spacer()
        }
    }

    private var severityBadgeColor: Color {
        switch engine.postureState.severity {
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        case .good: return .green
        }
    }

    private func badge(_ text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
            }
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Deviation Meter

    private var deviationMeter: some View {
        HStack(spacing: 8) {
            Text("Movement")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))

                    let fill = min(engine.postureState.deviationScore * 3, 1.0)
                    Capsule()
                        .fill(deviationColor(fill))
                        .frame(width: max(0, fill * geo.size.width))
                        .animation(.easeInOut(duration: 0.3), value: engine.postureState.deviationScore)
                }
            }
            .frame(height: 6)
        }
    }

    private func deviationColor(_ value: CGFloat) -> Color {
        if value < 0.3 { return .green }
        if value < 0.6 { return .yellow }
        return .red
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button {
                engine.toggleMonitoring()
            } label: {
                Label(
                    engine.isMonitoring ? "Stop" : "Start",
                    systemImage: engine.isMonitoring ? "stop.fill" : "play.fill"
                )
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isMonitoring ? .red : .blue)

            Button {
                engine.startCalibration()
            } label: {
                Label(
                    engine.calibrationData != nil ? "Recalibrate" : "Calibrate",
                    systemImage: "scope"
                )
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(engine.isCalibrating)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Privacy: No images stored")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
}
