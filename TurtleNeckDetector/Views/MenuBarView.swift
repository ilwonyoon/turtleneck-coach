import SwiftUI

/// Main popover content shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var engine: PostureEngine
    // Settings now opens in separate window via SettingsWindowController
    @State private var showDashboard = false
    @State private var refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var showCalibrationToast = false
    @State private var lastCalibrationSuccess: Bool?

    /// Single accent color derived from held severity — synced with menu bar.
    private var accentColor: Color {
        guard engine.isMonitoring, engine.calibrationData != nil, !engine.menuBarIsIdle else { return .gray }
        return engine.menuBarSeverityColor
    }

    private var cameraAspectRatio: CGFloat {
        guard let frame = engine.currentFrame else { return 4.0 / 3.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Error banner
                    if let error = engine.lastError {
                        errorBanner(error)
                    }

                    // LIVE VIEW section
                    if engine.isMonitoring {
                        section("LIVE VIEW") {
                            CameraPreviewView(
                                frame: engine.currentFrame,
                                joints: engine.currentJoints
                            )
                            .frame(maxWidth: .infinity)
                            .aspectRatio(cameraAspectRatio, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color(.separatorColor), lineWidth: 1)
                            )
                            .overlay(cvaOverlay, alignment: .topTrailing)
                            .overlay(alignment: .bottom) {
                                if engine.currentFrame != nil && !engine.bodyDetected {
                                    Text("No body detected")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                        .padding(.bottom, 8)
                                }
                            }
                        }
                    }

                    // Calibration overlay (active only)
                    if engine.isCalibrating {
                        CalibrationView(
                            progress: engine.calibrationProgress,
                            message: engine.calibrationMessage
                        )
                    }

                    // Unified posture card (score + status + badges)
                    if engine.isMonitoring && !engine.isCalibrating && engine.bodyDetected {
                        VStack(spacing: 12) {
                            PostureScoreView(
                                score: engine.postureScore,
                                emoji: engine.postureEmoji,
                                accentColor: accentColor
                            )
                            .animation(.easeInOut(duration: 0.8), value: engine.postureScore)

                            Divider()
                            statusCard

                            Divider()
                            badgesRow
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        section(nil) {
                            statusCard
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Controls
                    controlButtons
                }
                .padding(16)
            }
            .overlay(alignment: .top) {
                calibrationToast
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
        .onChange(of: engine.calibrationSuccess) { _, newValue in
            guard let success = newValue else { return }
            lastCalibrationSuccess = success
            withAnimation(.easeInOut(duration: 0.3)) {
                showCalibrationToast = true
            }
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCalibrationToast = false
                }
                engine.calibrationSuccess = nil
            }
        }
        .onChange(of: showDashboard) { _, show in
            if show {
                DashboardWindowController.shared.show(engine: engine)
                showDashboard = false
            }
        }
    }

    // MARK: - Section Helper

    private func section(_ title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("PT Turtle")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                showDashboard = true
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            Button {
                SettingsWindowController.shared.show(engine: engine)
            } label: {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
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

    // MARK: - Calibration Toast

    private var calibrationToast: some View {
        Group {
            if showCalibrationToast, let success = lastCalibrationSuccess {
                HStack(spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                    Text(success ? "Calibrated" : engine.calibrationMessage)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusMainText)
                    .font(.subheadline.weight(.medium))
                Text(statusSubText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var statusMainText: String {
        guard engine.isMonitoring else { return "Paused" }
        guard engine.calibrationData != nil else { return "Set your baseline" }
        if engine.isCalibrating { return "Reading your posture..." }

        // Head turned sideways — show rotation-specific main text
        let absYaw = abs(engine.currentHeadYaw)
        if absYaw > 15 {
            return absYaw > 30 ? "Head turned away" : "Head slightly turned"
        }

        switch engine.menuBarSeverity {
        case .good:
            let msg = FeedbackEngine.goodMessage(forDuration: engine.goodPostureDuration)
            return msg.main
        case .correction:
            return "Tuck your chin"
        case .bad:
            return "Reset your posture"
        case .away:
            return "Away"
        }
    }

    private var statusSubText: String {
        guard engine.isMonitoring else { return "Tap Start when you're ready." }
        guard engine.calibrationData != nil else { return "Sit tall and hit Calibrate." }
        if engine.isCalibrating { return "Hold still. Almost there." }

        switch engine.menuBarSeverity {
        case .good:
            let msg = FeedbackEngine.goodMessage(forDuration: engine.goodPostureDuration)
            return msg.sub
        case .correction, .bad, .away:
            return FeedbackEngine.severityTip(for: engine.menuBarSeverity, headYaw: engine.currentHeadYaw)
        }
    }

    // MARK: - Badges

    private var badgesRow: some View {
        HStack(spacing: 6) {
            badge(engine.cameraPosition.rawValue.capitalized, icon: "camera")

            if engine.postureState.usingFallback {
                badge("Eye Mode", icon: "eye")
            }

            if engine.goodPostureDuration >= 30 {
                badge(FeedbackEngine.formatTime(engine.goodPostureDuration) + " streak", icon: "flame")
            }

            Spacer()
        }
    }

    private func badge(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
            }
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Head Position Widget

    private var headPositionWidget: some View {
        HStack(spacing: 10) {
            Text("Head")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)

            // Crosshair showing head yaw (x) and pitch (y)
            let size: CGFloat = 36
            let maxYaw: CGFloat = 40    // ±40° maps to edges
            let maxPitch: CGFloat = 30  // ±30° maps to edges

            // Clamp and normalize to -1...1
            let nx = min(1, max(-1, engine.currentHeadYaw / maxYaw))
            let ny = min(1, max(-1, engine.currentHeadPitch / maxPitch))

            ZStack {
                // Background circle
                Circle()
                    .fill(Color(.separatorColor).opacity(0.15))

                // Crosshair lines
                Path { p in
                    p.move(to: CGPoint(x: size / 2, y: 2))
                    p.addLine(to: CGPoint(x: size / 2, y: size - 2))
                }
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)

                Path { p in
                    p.move(to: CGPoint(x: 2, y: size / 2))
                    p.addLine(to: CGPoint(x: size - 2, y: size / 2))
                }
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 0.5)

                // Head position dot
                // x: yaw (positive = left in mirrored view, so negate for natural feel)
                // y: pitch (positive = forward/down)
                let dotX = size / 2 + (-nx) * (size / 2 - 4)
                let dotY = size / 2 + ny * (size / 2 - 4)
                let dotColor: Color = (abs(nx) < 0.375 && ny < 0.5) ? .green : .orange

                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .position(x: dotX, y: dotY)
                    .animation(.easeOut(duration: 0.15), value: nx)
                    .animation(.easeOut(duration: 0.15), value: ny)
            }
            .frame(width: size, height: size)

            // Labels
            VStack(alignment: .leading, spacing: 1) {
                let pitchLabel = engine.currentHeadPitch < 3 ? "Straight" :
                                 engine.currentHeadPitch < 15 ? "Slight tilt" : "Forward"
                let yawLabel = abs(engine.currentHeadYaw) < 10 ? "Center" :
                               abs(engine.currentHeadYaw) < 25 ? "Turned" : "Far turn"

                Text(pitchLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(yawLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(height: 40)
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
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
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
