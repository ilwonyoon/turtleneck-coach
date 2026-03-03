import SwiftUI

/// Settings panel for camera position and monitoring interval.
struct SettingsView: View {
    @ObservedObject var engine: PostureEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            // Camera position
            VStack(alignment: .leading, spacing: 6) {
                Text("Camera Position")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Camera", selection: $engine.cameraPosition) {
                    ForEach(CameraPosition.allCases, id: \.self) { pos in
                        Text(pos.rawValue.capitalized).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Monitoring interval
            VStack(alignment: .leading, spacing: 6) {
                Text("Check Interval: \(Int(engine.monitoringInterval))s")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Slider(value: $engine.monitoringInterval, in: 2...10, step: 1)
            }

            Divider()

            // Reset calibration
            Button(role: .destructive) {
                engine.resetCalibration()
            } label: {
                Label("Reset Calibration", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
            }
            .disabled(engine.calibrationData == nil)
        }
        .padding(12)
    }
}
