import SwiftUI
import AppKit


struct OnboardingView: View {
    @ObservedObject var engine: PostureEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var isRequestingPermissions = false
    @State private var cameraDenied = false
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
            default:
                calibrateStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private var welcomeStep: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

            Text("Turtleneck Coach")
                .font(DS.Onboarding.title)

            Text("Monitors your posture while you work.\n100% on-device.")
                .font(DS.Onboarding.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            if cameraDenied {
                cameraDeniedBanner
            }

            Text("Sit upright to start.")
                .font(DS.Onboarding.detail)
                .foregroundStyle(.secondary)

            Button {
                requestPermissionsAndStart()
            } label: {
                Text(isRequestingPermissions ? "Requesting Access..." : "Start Monitoring")
                    .font(DS.Onboarding.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingPermissions)
        }
    }

    private var cameraDeniedBanner: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .top, spacing: DS.Space.sm) {
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
                hasCompletedOnboarding = true
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
                hasCompletedOnboarding = true
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard !didAttemptNotificationRequest else { return }
        didAttemptNotificationRequest = true
        Task {
            await TurtleneckCoachApp.requestNotificationPermissionIfNeeded()
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
