import SwiftUI
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var engine: PostureEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var step = 0
    @State private var isRequestingPermissions = false
    @State private var cameraDenied = false

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 16)

            Image(systemName: "tortoise.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.green)

            Text("PT Turtle")
                .font(.title3.weight(.semibold))

            Text("Monitors your posture while you work. No images stored.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 16)

            if cameraDenied {
                cameraDeniedBanner
            }

            Button {
                requestPermissionsAndStart()
            } label: {
                Text(isRequestingPermissions ? "Requesting Access..." : "Get Started")
                    .font(.subheadline.weight(.medium))
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
                    .foregroundStyle(.orange)
                Text("Camera access is required to monitor posture.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            if let cameraSettingsURL {
                Link("Open System Settings", destination: cameraSettingsURL)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var calibrateStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sit up straight")
                .font(.title3.weight(.semibold))

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

            if engine.isCalibrating {
                CalibrationView(
                    progress: engine.calibrationProgress,
                    message: engine.calibrationMessage
                )
                .background(.thickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if engine.calibrationSuccess == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calibration did not complete.")
                        .font(.subheadline.weight(.medium))
                    Text("Keep your head centered and hold still.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Retry") {
                    engine.startCalibration()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Starting calibration...")
                        .font(.subheadline.weight(.medium))
                    Text("Face the camera and hold still.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            if engine.calibrationSuccess == true && engine.calibrationData != nil {
                step = 2
            }
        }
        .onChange(of: engine.isCalibrating) { _, isCalibrating in
            guard !isCalibrating else { return }
            if engine.calibrationSuccess == true && engine.calibrationData != nil {
                step = 2
            }
        }
    }

    private var scoreZonesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Score Zones")
                .font(.title3.weight(.semibold))

            VStack(spacing: 14) {
                scoreZoneRow(
                    color: .green,
                    title: "Great",
                    description: "Score 75-100. You're in great posture."
                )
                scoreZoneRow(
                    color: .yellow,
                    title: "Adjust",
                    description: "Score 50-74. Chin may be drifting forward."
                )
                scoreZoneRow(
                    color: .orange,
                    title: "Reset",
                    description: "Score below 50. Time to sit up and reset."
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 0)

            Button("Start Monitoring") {
                hasCompletedOnboarding = true
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
        }
    }

    private func scoreZoneRow(color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func requestPermissionsAndStart() {
        guard !isRequestingPermissions else { return }

        isRequestingPermissions = true
        cameraDenied = false

        Task {
            let cameraGranted = await TurtleNeckDetectorApp.requestAllPermissions()
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
