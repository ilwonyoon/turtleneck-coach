import SwiftUI

/// Guided calibration overlay with posture checklist and progress.
/// Only shows the active calibrating state — result is handled by toast in MenuBarView.
struct CalibrationView: View {
    let progress: CGFloat
    let message: String

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Text("Reading your posture...")
                .font(DS.Font.headline)

            // Posture checklist
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Quick setup")
                    .font(DS.Font.subheadBold)

                checkItem("Feet flat on the floor")
                checkItem("Back against the chair")
                checkItem("Ears over shoulders")
                checkItem("Chin gently tucked")
                checkItem("Shoulders down and relaxed")
            }
            .padding(10) // DS: one-off
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            Text("Hold still for a few seconds.")
                .font(DS.Font.sysCaption)
                .foregroundColor(.secondary)

            // Progress bar
            ProgressView(value: progress)
                .tint(.primary.opacity(0.6))

            Text("\(Int(progress * 100))%")
                .font(DS.Font.sysCaption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(DS.Space.xl)
        .background(DS.Surface.subtle)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    private func checkItem(_ text: String) -> some View {
        HStack(spacing: 6) { // DS: one-off
            Image(systemName: "checkmark")
                .font(DS.Font.sysCaption2)
                .foregroundColor(.secondary)
            Text(text)
                .font(DS.Font.sysCaption)
                .foregroundColor(.secondary)
        }
    }
}
