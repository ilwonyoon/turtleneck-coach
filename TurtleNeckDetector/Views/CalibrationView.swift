import SwiftUI

/// Guided calibration overlay with posture checklist and progress.
/// Only shows the active calibrating state — result is handled by toast in MenuBarView.
struct CalibrationView: View {
    let progress: CGFloat
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Reading your posture...")
                .font(.headline)

            // Posture checklist
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick setup")
                    .font(.subheadline.weight(.semibold))

                checkItem("Feet flat on the floor")
                checkItem("Back against the chair")
                checkItem("Ears over shoulders")
                checkItem("Chin gently tucked")
                checkItem("Shoulders down and relaxed")
            }
            .padding(10)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Hold still for a few seconds.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Progress bar
            ProgressView(value: progress)
                .tint(.primary.opacity(0.6))

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func checkItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
