import SwiftUI

/// Guided calibration overlay with posture checklist and progress.
struct CalibrationView: View {
    let progress: CGFloat
    let message: String
    let success: Bool?

    var body: some View {
        VStack(spacing: 14) {
            if let success {
                // Result state
                resultView(success: success)
            } else {
                // Calibrating state
                calibratingView
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var calibratingView: some View {
        VStack(spacing: 12) {
            Text("Calibrating...")
                .font(.headline)
                .foregroundColor(.yellow)

            // Posture checklist
            VStack(alignment: .leading, spacing: 4) {
                Text("Correct Posture Checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.yellow)

                checkItem("Feet flat on the floor")
                checkItem("Back straight against chair")
                checkItem("Ears directly above shoulders")
                checkItem("Chin slightly tucked")
                checkItem("Shoulders relaxed, not hunched")
            }
            .padding(10)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Hold this posture while calibrating")
                .font(.caption)
                .foregroundColor(.secondary)

            // Progress bar
            ProgressView(value: progress)
                .tint(.green)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private func resultView(success: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(success ? .green : .red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(success ? .green : .red)
                .multilineTextAlignment(.center)
        }
    }

    private func checkItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
