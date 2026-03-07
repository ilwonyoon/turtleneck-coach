import SwiftUI

/// Main popover content shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var engine: PostureEngine
    // Settings now opens in separate window via SettingsWindowController
    @State private var showDashboard = false
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
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.sm)

            Divider()

            ScrollView {
                VStack(spacing: DS.Space.lg) {
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
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
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
                                        .background(DS.Surface.subtle)
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
                                scoreColor: engine.postureScoreColor
                            )
                            .animation(.easeInOut(duration: 0.8), value: engine.postureScore)

                            Divider()
                            statusCard

                            Divider()
                            badgesRow
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.md)
                        .background(DS.Surface.overlay)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    } else {
                        section(nil) {
                            statusCard
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.Space.md)
                                .background(DS.Surface.card)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                        }
                    }

                    // Controls
                    controlButtons

                }
                .padding(DS.Space.lg)
            }
            .overlay(alignment: .top) {
                calibrationToast
            }

            Divider()

            // Footer
            footer
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
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
                    .font(DS.Font.caption)
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
            Text("Turtleneck Coach")
                .font(DS.Font.titleBold)
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
                    .font(DS.Font.mono)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
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
                        .font(DS.Font.subheadMedium)
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(DS.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentColor)
                .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusMainText)
                    .font(DS.Font.subheadMedium)
                Text(statusSubText)
                    .font(DS.Font.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            powerStateBadge
        }
    }

    private var statusMainText: String {
        guard engine.isMonitoring else { return "Paused" }
        if engine.isCalibrating { return "Calibrating..." }
        if engine.calibrationData == nil { return "Starting up..." }
        if engine.powerState == .inactive { return "Paused" }
        if engine.powerState == .drowsy && !engine.bodyDetected { return "Low Power" }

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
            if engine.postureState.classification == .lookingDown {
                return "Lift your gaze"
            }
            return "Tuck your chin"
        case .bad:
            return "Reset your posture"
        case .away:
            return "Away"
        }
    }

    private var statusSubText: String {
        guard engine.isMonitoring else { return "Tap Start when you're ready." }
        if engine.isCalibrating { return "Sit up straight. Hold still." }
        if engine.calibrationData == nil { return "Preparing camera..." }
        if engine.powerState == .inactive { return "No one detected. Probing every 6 seconds." }
        if engine.powerState == .drowsy && !engine.bodyDetected {
            return "No body detected. Slower checks to save battery."
        }

        switch engine.menuBarSeverity {
        case .good:
            let msg = FeedbackEngine.goodMessage(forDuration: engine.goodPostureDuration)
            return msg.sub
        case .correction, .bad, .away:
            return FeedbackEngine.severityTip(
                for: engine.menuBarSeverity,
                headYaw: engine.currentHeadYaw,
                classification: engine.postureState.classification
            )
        }
    }

    @ViewBuilder
    private var powerStateBadge: some View {
        if engine.isMonitoring && !engine.isCalibrating {
            switch engine.powerState {
            case .active:
                EmptyView()
            case .drowsy:
                badge("Low Power", icon: "moon.fill")
            case .inactive:
                badge("Paused", icon: "pause.fill")
            }
        }
    }

    // MARK: - Badges

    private var badgesRow: some View {
        HStack(spacing: 6) { // DS: one-off
            badge(engine.cameraPosition.rawValue.capitalized, icon: "camera")
            badge(contextBadgeText, icon: "viewfinder")

            if engine.postureState.usingFallback {
                badge("Eye Mode", icon: "eye")
            }

            if engine.goodPostureDuration >= 30 {
                badge(FeedbackEngine.formatTime(engine.goodPostureDuration) + " streak", icon: "flame")
            }

            Spacer()
        }
    }

    private var contextBadgeText: String {
        let context = engine.inferredCameraContext
        let isManual = engine.inferredContextSource == "manual"
        switch (context, isManual) {
        case (.desktop, true):
            return "Desktop Set"
        case (.laptop, true):
            return "Laptop Set"
        case (.desktop, false):
            return "Desk-like"
        case (.laptop, false):
            return "Laptop-like"
        case (.unknown, true):
            return "Context Set"
        case (.unknown, false):
            return "Context Auto"
        }
    }

    private func badge(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(DS.Font.badgeIcon)
            }
            Text(text)
                .font(DS.Font.mini)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, 3) // DS: one-off
        .background(.quaternary.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Head Position Widget

    private var headPositionWidget: some View {
        HStack(spacing: 10) {
            Text("Head")
                .font(DS.Font.caption)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)

            // Crosshair showing head yaw (x) and pitch (y)
            let size: CGFloat = 36 // DS: one-off (crosshair generator param)
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
                    .font(DS.Font.mini)
                    .foregroundColor(.secondary)
                Text(yawLabel)
                    .font(DS.Font.mini)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(height: DS.Size.headWidget)
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
                .font(DS.Font.subheadMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isMonitoring ? .red : .blue)

            if engine.isMonitoring && !engine.isCalibrating {
                Button {
                    engine.startCalibration()
                } label: {
                    Label("Recalibrate", systemImage: "scope")
                        .font(DS.Font.subheadMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            #if DEBUG
            if engine.isMonitoring && !engine.isCalibrating && engine.calibrationData != nil {
                HStack(spacing: 8) {
                    Button {
                        engine.startDebugCapture(label: "GOOD_POSTURE")
                    } label: {
                        Label("Good 5s", systemImage: "checkmark.circle")
                            .font(DS.Font.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(engine.debugCaptureLabel != nil)

                    Button {
                        engine.startDebugCapture(label: "TURTLE_NECK")
                    } label: {
                        Label("Turtle 5s", systemImage: "tortoise")
                            .font(DS.Font.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(engine.debugCaptureLabel != nil)
                }

                if let label = engine.debugCaptureLabel {
                    Text("Recording: \(label)...")
                        .font(DS.Font.mini)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                }
            }
            #endif
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(DS.Font.caption)
            }
            if message.contains("Camera access denied") {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(DS.Font.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Footer

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var footer: some View {
        HStack {
            Text("v\(appVersion)")
                .font(DS.Font.micro)
                .foregroundColor(.secondary)
            Text("\u{00B7}")
                .foregroundStyle(.quaternary)
            Text("No images stored")
                .font(DS.Font.micro)
                .foregroundColor(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(DS.Font.caption)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
}
