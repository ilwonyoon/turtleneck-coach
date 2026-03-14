import SwiftUI
import AppKit
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var engine: PostureEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var isRequestingPermissions = false
    @State private var cameraDenied = false
    @State private var notificationsDenied = false
    @State private var didAttemptNotificationRequest = false

    @AppStorage(SensitivityMode.storageKey)
    private var sensitivityModeRawValue = SensitivityMode.defaultMode.rawValue

    private var sensitivityModeBinding: Binding<SensitivityMode> {
        Binding(
            get: { SensitivityMode(rawValue: sensitivityModeRawValue) ?? .balanced },
            set: { sensitivityModeRawValue = $0.rawValue }
        )
    }

    private var cameraAspectRatio: CGFloat {
        guard let frame = engine.currentFrame else { return 4.0 / 3.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    private var cameraSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0:
                welcomeStep
            case 1:
                cameraAnywhereStep
            case 2:
                sensitivityStep
            case 3:
                calibrateStep
            default:
                scoreZonesStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private var welcomeStep: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer(minLength: DS.Space.lg)

            Image(systemName: "tortoise.fill")
                .font(DS.Font.display)
                .symbolRenderingMode(.palette)
                .foregroundStyle(DS.Palette.green)

            Text("Turtleneck Coach")
                .font(DS.Font.titleBold)

            Text("Reduce your bad posture time while you work.\nNo images are stored or sent anywhere.")
                .font(DS.Font.subheadMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "camera.fill", color: .blue,
                           title: "Camera Access",
                           detail: "Tracks your head and shoulders to detect when you start slouching.")
                featureRow(icon: "bell.fill", color: .orange,
                           title: "Notifications",
                           detail: "Gentle reminders when you've been leaning forward for a while.")
                featureRow(icon: "lock.shield.fill", color: .green,
                           title: "Private by Design",
                           detail: "All processing happens on your Mac. Nothing leaves your device.")
            }
            .padding(DS.Space.md)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

            Spacer(minLength: DS.Space.lg)

            if cameraDenied {
                cameraDeniedBanner
            }

            Text("When you start, sit upright for a few seconds so Turtleneck Coach can learn your posture for your current camera position.")
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button {
                requestPermissionsAndStart()
            } label: {
                Text(isRequestingPermissions ? "Requesting Access..." : "Start Monitoring")
                    .font(DS.Font.subheadMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingPermissions)
        }
    }

    private var cameraDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Palette.orange)
                Text("Camera access is required to monitor posture.")
                    .font(DS.Font.subheadMedium)
                    .foregroundStyle(.primary)
            }

            if let cameraSettingsURL {
                Link("Open System Settings", destination: cameraSettingsURL)
                    .font(DS.Font.subheadMedium)
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var cameraAnywhereStep: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer(minLength: DS.Space.lg)

            Image(systemName: "camera.on.rectangle.fill")
                .font(DS.Font.display)
                .foregroundStyle(.blue)

            Text("Works With Any Camera")
                .font(DS.Font.titleBold)

            Text("Built-in webcam, external monitor camera, or laptop on the side — Turtleneck Coach adapts automatically.")
                .font(DS.Font.subheadMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) { // DS: one-off
                featureRow(icon: "laptopcomputer", color: .blue,
                           title: "Built-in Camera",
                           detail: "Your MacBook's FaceTime camera works perfectly.")
                featureRow(icon: "display", color: .purple,
                           title: "External Display",
                           detail: "Studio Display, webcams, or any USB camera.")
                featureRow(icon: "arrow.triangle.2.circlepath", color: .green,
                           title: "Auto-Detect",
                           detail: "Adjusts scoring based on camera angle and position.")
            }
            .padding(DS.Space.md)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

            Spacer(minLength: DS.Space.lg)

            Button {
                step = 2
            } label: {
                Text("Next")
                    .font(DS.Font.subheadMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sensitivityStep: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer(minLength: DS.Space.lg)

            Image(systemName: "slider.horizontal.3")
                .font(DS.Font.display)
                .foregroundStyle(DS.Palette.green)

            Text("Choose Your Level")
                .font(DS.Font.titleBold)

            Text("This controls how scores are calculated.\nYou can change this anytime in Settings.")
                .font(DS.Font.subheadMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(spacing: 8) { // DS: one-off
                sensitivityCard(
                    mode: .relaxed,
                    icon: "leaf.fill",
                    color: .green,
                    detail: "Gentler scores. Recommended if you're just starting."
                )
                sensitivityCard(
                    mode: .balanced,
                    icon: "equal.circle.fill",
                    color: .blue,
                    detail: "Standard scores for daily monitoring."
                )
                sensitivityCard(
                    mode: .strict,
                    icon: "bolt.fill",
                    color: .orange,
                    detail: "Tighter scores for those with good posture."
                )
            }

            Spacer(minLength: DS.Space.lg)

            Button {
                step = 3
                engine.startMonitoring()
                engine.startCalibration()
            } label: {
                Text("Next")
                    .font(DS.Font.subheadMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func sensitivityCard(mode: SensitivityMode, icon: String, color: Color, detail: String) -> some View {
        let isSelected = (SensitivityMode(rawValue: sensitivityModeRawValue) ?? .balanced) == mode

        return Button {
            sensitivityModeRawValue = mode.rawValue
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: icon)
                    .font(DS.Font.icon)
                    .foregroundStyle(color)
                    .frame(width: DS.Size.iconFrame)

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.displayName)
                        .font(DS.Font.subheadBold)
                    Text(detail)
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                        .font(DS.Font.icon)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 10) // DS: one-off
            .background(isSelected ? color.opacity(0.08) : Color.clear)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var calibrateStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { // DS: one-off
                Text("Sit up straight")
                    .font(DS.Font.titleBold)

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

                if engine.isCalibrating {
                    CalibrationView(
                        progress: engine.calibrationProgress,
                        message: engine.calibrationMessage
                    )
                    .background(DS.Surface.overlay)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                } else if engine.calibrationSuccess == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Calibration did not complete.")
                            .font(DS.Font.subheadMedium)
                        Text("Look straight ahead in your usual setup and hold still.")
                            .font(DS.Font.subheadMedium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Surface.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

                    Button("Retry") {
                        engine.startCalibration()
                    }
                    .font(DS.Font.subheadMedium)
                    .buttonStyle(.borderedProminent)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Starting calibration...")
                            .font(DS.Font.subheadMedium)
                        Text("Look straight ahead in your usual setup and hold still.")
                            .font(DS.Font.subheadMedium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Surface.card)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }
        }
        .onAppear {
            if engine.calibrationSuccess == true && engine.calibrationData != nil {
                step = 4
            }
        }
        .task {
            // Brief delay so the popover is fully stable before the system dialog appears.
            try? await Task.sleep(for: .seconds(1.5))
            requestNotificationPermissionIfNeeded()
        }
        .onChange(of: engine.isCalibrating) { _, isCalibrating in
            guard !isCalibrating else { return }
            if engine.calibrationSuccess == true && engine.calibrationData != nil {
                step = 4
            }
        }
    }

    private var scoreZonesStep: some View {
        VStack(spacing: 0) {
            // Success badge
            Image(systemName: "checkmark.circle.fill")
                .font(DS.Font.heroIcon)
                .foregroundStyle(DS.Palette.green)
                .padding(.top, DS.Space.lg)

            Text("Calibration Complete")
                .font(DS.Font.titleBold)
                .padding(.top, 10)

            Text("Here's how your score works:")
                .font(DS.Font.subhead)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Score zone cards
            VStack(spacing: 8) {
                scoreZoneCard(
                    color: .green,
                    icon: "face.smiling",
                    title: "Great",
                    range: "75–100",
                    detail: "You're in great posture."
                )
                scoreZoneCard(
                    color: .yellow,
                    icon: "exclamationmark.triangle",
                    title: "Adjust",
                    range: "50–74",
                    detail: "Chin may be drifting forward."
                )
                scoreZoneCard(
                    color: .orange,
                    icon: "arrow.up.circle",
                    title: "Reset",
                    range: "Below 50",
                    detail: "Time to sit up and reset."
                )
            }
            .padding(.top, DS.Space.lg)

            // Menu bar hint
            HStack(spacing: 8) { // DS: one-off
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(DS.Font.icon)
                    .foregroundStyle(.secondary)
                Text("Look for the turtle icon in your menu bar to check your score anytime.")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .padding(.top, DS.Space.md)

            // Notification denied banner
            if notificationsDenied {
                notificationDeniedBanner
                    .padding(.top, DS.Space.md)
            }

            // CTA button
            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("Start Monitoring")
                    .font(DS.Font.subheadMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, DS.Space.lg)
        }
        .onAppear {
            checkNotificationStatus()
        }
    }

    private var notificationDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(DS.Palette.orange)
                Text("Notifications are off")
                    .font(DS.Font.subheadBold)
            }
            Text("Enable notifications in System Settings to get posture alerts.")
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(DS.Font.caption)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsDenied = settings.authorizationStatus == .denied
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard !didAttemptNotificationRequest else { return }
        didAttemptNotificationRequest = true
        Task {
            await TurtleneckCoachApp.requestNotificationPermissionIfNeeded()
            checkNotificationStatus()
        }
    }

    private func scoreZoneCard(color: Color, icon: String, title: String, range: String, detail: String) -> some View {
        HStack(spacing: DS.Space.md) {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(color.opacity(0.8))
                .frame(width: DS.Size.colorAccentBar)

            Image(systemName: icon)
                .font(DS.Font.icon)
                .foregroundStyle(color)
                .frame(width: DS.Size.iconFrame)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(DS.Font.subheadBold)
                    Text(range)
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Capsule())
                }
                Text(detail)
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, 10) // DS: one-off
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) { // DS: one-off
            Image(systemName: icon)
                .font(DS.Font.callout)
                .foregroundStyle(color)
                .frame(width: DS.Size.featureIconFrame, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.subheadMedium)
                Text(detail)
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestPermissionsAndStart() {
        guard !isRequestingPermissions else { return }

        isRequestingPermissions = true
        cameraDenied = false

        Task {
            let cameraGranted = await TurtleneckCoachApp.requestAllPermissions()
            await MainActor.run {
                isRequestingPermissions = false
                if cameraGranted {
                    step = 1
                } else {
                    cameraDenied = true
                }
            }
        }
    }
}
