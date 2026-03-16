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
                .font(DS.Onboarding.heroIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(DS.Palette.green)

            Text("Turtleneck Coach")
                .font(DS.Onboarding.title)

            HStack(spacing: 4) {
                Text("Posture reminders, 100% on-device.")
                    .font(DS.Onboarding.body)
                    .foregroundStyle(.secondary)

                Image(systemName: "info.circle")
                    .font(DS.Onboarding.detail)
                    .foregroundStyle(.tertiary)
                    .help("All analysis runs on your Mac.\nNo images are stored or sent anywhere.")
            }

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "camera.fill", color: .blue,
                           title: "Camera",
                           detail: "Tracks head & shoulders.")
                featureRow(icon: "bell.fill", color: .orange,
                           title: "Notifications",
                           detail: "Alerts when slouching too long.")
            }
            .padding(DS.Space.md)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

            Spacer(minLength: DS.Space.md)

            if cameraDenied {
                cameraDeniedBanner
            }

            Text("Sit upright when you start — we'll learn your posture.")
                .font(DS.Onboarding.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button {
                requestPermissionsAndStart()
            } label: {
                Text(isRequestingPermissions ? "Requesting Access..." : "Start Monitoring")
                    .font(DS.Onboarding.bodyMedium)
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
                step = 2
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
                step = 2
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
                .font(DS.Onboarding.featureIcon)
                .foregroundStyle(color)
                .frame(width: DS.Onboarding.featureIconFrame, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Onboarding.bodyMedium)
                Text(detail)
                    .font(DS.Onboarding.detail)
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
                    engine.startMonitoring()
                } else {
                    cameraDenied = true
                }
            }
        }
    }
}
