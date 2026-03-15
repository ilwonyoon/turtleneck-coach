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

    private var cameraAspectRatio: CGFloat {
        guard let frame = engine.currentFrame else { return 4.0 / 3.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    private var cameraSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0: welcomeStep
            case 1: cameraAnywhereStep
            case 2: sensitivityStep
            case 3: calibrateStep
            default: scoreZonesStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40) // DS: one-off (onboarding)
        .padding(.vertical, 36) // DS: one-off (onboarding)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero: App logo character
            // TODO: Replace with Turtleneck_coach_mac_logo.png
            onboardingImage("onboarding_welcome")
                .frame(width: 120, height: 120) // DS: one-off (onboarding hero)

            Text("Turtleneck Coach")
                .font(DS.Onboarding.title)
                .padding(.top, DS.Space.lg)

            Text("Monitors your posture while you work.\nPrivate — nothing leaves your Mac.")
                .font(DS.Onboarding.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, DS.Space.sm)

            VStack(alignment: .leading, spacing: DS.Space.lg) {
                featureRow(icon: "camera.fill", color: .blue,
                           title: "Camera",
                           detail: "Detects head and shoulder position.")
                featureRow(icon: "bell.fill", color: .orange,
                           title: "Notifications",
                           detail: "Gentle alerts when posture drifts.")
                featureRow(icon: "lock.shield.fill", color: .green,
                           title: "Private",
                           detail: "All processing stays on-device.")
            }
            .padding(DS.Space.xl)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.top, DS.Space.xxl)

            // Disclaimer
            Text("This is not a medical product. Forward head posture improves with stretching, exercise, and good habits. Turtleneck Coach helps you stay aware of your posture throughout the day.")
                .font(DS.Onboarding.detail)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, DS.Space.lg)

            Spacer()

            if cameraDenied {
                cameraDeniedBanner
                    .padding(.bottom, DS.Space.md)
            }

            Button {
                requestPermissionsAndStart()
            } label: {
                Text(isRequestingPermissions ? "Requesting Access…" : "Get Started")
                    .font(DS.Onboarding.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingPermissions)
        }
    }

    private var cameraDeniedBanner: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Palette.orange)
            Text("Camera access is required.")
                .font(DS.Onboarding.body)
            Spacer()
            if let cameraSettingsURL {
                Link("Open Settings", destination: cameraSettingsURL)
                    .font(DS.Onboarding.body)
            }
        }
        .padding(DS.Space.lg)
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Step 1: Camera Anywhere

    private var cameraAnywhereStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero: Camera placement illustration
            // TODO: Replace with custom illustration
            onboardingImage("onboarding_camera")
                .frame(width: 120, height: 120) // DS: one-off (onboarding hero)

            Text("Place Your Camera Anywhere")
                .font(DS.Onboarding.title)
                .padding(.top, DS.Space.lg)

            Text("Above, below, or to the side — scoring adjusts automatically to your camera's position.")
                .font(DS.Onboarding.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, DS.Space.sm)

            Spacer()

            Button {
                step = 2
            } label: {
                Text("Next")
                    .font(DS.Onboarding.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Step 2: Sensitivity

    private var sensitivityStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero: Good turtle vs Severe turtle side by side
            // TODO: Replace with turtle_good + turtle_severe illustration
            HStack(spacing: DS.Space.xl) {
                onboardingImage("onboarding_sensitivity_good")
                    .frame(width: 80, height: 80) // DS: one-off
                onboardingImage("onboarding_sensitivity_bad")
                    .frame(width: 80, height: 80) // DS: one-off
            }

            Text("Choose Your Level")
                .font(DS.Onboarding.title)
                .padding(.top, DS.Space.lg)

            Text("Controls how scores are calculated.\nChange anytime in Settings.")
                .font(DS.Onboarding.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, DS.Space.sm)

            VStack(spacing: DS.Space.sm) {
                sensitivityCard(
                    mode: .relaxed, icon: "leaf.fill", color: .green,
                    detail: "Gentler scoring — good for beginners."
                )
                sensitivityCard(
                    mode: .balanced, icon: "equal.circle.fill", color: .blue,
                    detail: "Standard daily monitoring."
                )
                sensitivityCard(
                    mode: .strict, icon: "bolt.fill", color: .orange,
                    detail: "Tighter scoring for good posture."
                )
            }
            .padding(.top, DS.Space.xxl)

            Spacer()

            Button {
                step = 3
                engine.startMonitoring()
                engine.startCalibration()
            } label: {
                Text("Next")
                    .font(DS.Onboarding.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.sm)
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
                    .font(DS.Onboarding.icon)
                    .foregroundStyle(color)
                    .frame(width: DS.Onboarding.iconFrame)

                VStack(alignment: .leading, spacing: 2) { // DS: one-off
                    Text(mode.displayName)
                        .font(DS.Onboarding.bodyMedium)
                    Text(detail)
                        .font(DS.Onboarding.detail)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                        .font(DS.Onboarding.icon)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
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

    // MARK: - Step 3: Calibrate

    private var calibrateStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack {
                Text("Sit up straight")
                    .font(DS.Onboarding.title)
                Spacer()
                // Small turtle_good as posture hint
                // TODO: Replace with turtle_good.png
                onboardingImage("onboarding_calibrate_hint")
                    .frame(width: 48, height: 48) // DS: one-off
            }

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
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Calibration did not complete.")
                        .font(DS.Onboarding.bodyMedium)
                    Text("Look straight ahead and hold still.")
                        .font(DS.Onboarding.body)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

                Button("Retry") {
                    engine.startCalibration()
                }
                .font(DS.Onboarding.bodyMedium)
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Starting calibration…")
                        .font(DS.Onboarding.bodyMedium)
                    Text("Look straight ahead and hold still.")
                        .font(DS.Onboarding.body)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Surface.card)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }

            Spacer()
        }
        .onAppear {
            if engine.calibrationSuccess == true && engine.calibrationData != nil {
                step = 4
            }
        }
        .task {
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

    // MARK: - Step 4: Score Zones

    private var scoreZonesStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero: Happy turtle (good posture achieved)
            // TODO: Replace with turtle_good.png
            onboardingImage("onboarding_complete")
                .frame(width: 100, height: 100) // DS: one-off

            Text("You're All Set")
                .font(DS.Onboarding.title)
                .padding(.top, DS.Space.lg)

            Text("Here's how scoring works:")
                .font(DS.Onboarding.body)
                .foregroundStyle(.secondary)
                .padding(.top, DS.Space.sm)

            VStack(spacing: DS.Space.sm) {
                scoreZoneCard(color: .green, icon: "face.smiling",
                              title: "Great", range: "75–100")
                scoreZoneCard(color: .yellow, icon: "exclamationmark.triangle",
                              title: "Adjust", range: "50–74")
                scoreZoneCard(color: .orange, icon: "arrow.up.circle",
                              title: "Reset", range: "Below 50")
            }
            .padding(.top, DS.Space.xxl)

            // Menu bar hint
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(DS.Onboarding.featureIcon)
                    .foregroundStyle(.secondary)
                Text("Check your score anytime from the menu bar.")
                    .font(DS.Onboarding.detail)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .padding(.top, DS.Space.lg)

            if notificationsDenied {
                notificationDeniedBanner
                    .padding(.top, DS.Space.sm)
            }

            Spacer()

            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("Start Monitoring")
                    .font(DS.Onboarding.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            checkNotificationStatus()
        }
    }

    private var notificationDeniedBanner: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(DS.Palette.orange)
            Text("Notifications are off.")
                .font(DS.Onboarding.body)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(DS.Onboarding.detail)
        }
        .padding(DS.Space.lg)
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Shared Components

    /// Placeholder for onboarding images.
    /// Shows a dashed rectangle with the image name until real assets are added.
    @ViewBuilder
    private func onboardingImage(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.quaternary)

            VStack(spacing: DS.Space.xs) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.quaternary)
                Text(name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func scoreZoneCard(color: Color, icon: String, title: String, range: String) -> some View {
        HStack(spacing: DS.Space.md) {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(color.opacity(0.8))
                .frame(width: DS.Size.colorAccentBar)

            Image(systemName: icon)
                .font(DS.Onboarding.icon)
                .foregroundStyle(color)
                .frame(width: DS.Onboarding.iconFrame)

            Text(title)
                .font(DS.Onboarding.bodyMedium)

            Spacer()

            Text(range)
                .font(DS.Onboarding.detail)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .background(DS.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(DS.Onboarding.featureIcon)
                .foregroundStyle(color)
                .frame(width: DS.Onboarding.featureIconFrame, alignment: .center)
                .padding(.top, 1) // DS: one-off

            VStack(alignment: .leading, spacing: 2) { // DS: one-off
                Text(title)
                    .font(DS.Onboarding.bodyMedium)
                Text(detail)
                    .font(DS.Onboarding.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

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
