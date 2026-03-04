import SwiftUI

/// Compact calibration indicator — progress bar with inline status.
struct CalibrationView: View {
    let progress: CGFloat
    let message: String

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            HStack {
                Text("Calibrating")
                    .font(DS.Font.subheadBold)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(DS.Font.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .tint(.primary.opacity(0.6))

            Text("Sit up straight — hold still")
                .font(DS.Font.caption)
                .foregroundColor(.secondary)
        }
        .padding(DS.Space.md)
        .background(DS.Surface.subtle)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}
