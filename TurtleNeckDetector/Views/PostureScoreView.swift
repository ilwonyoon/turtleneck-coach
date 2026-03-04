import SwiftUI

/// Apple Activity Ring style posture score display.
struct PostureScoreView: View {
    let score: Int
    let emoji: String
    let scoreColor: Color

    private var scoreLabel: String {
        if score >= 80 { return "Strong posture" }
        if score >= 60 { return "Quick adjustment" }
        if score >= 40 { return "Time to reset" }
        return "Take a short break"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Activity Ring with emoji
            ZStack {
                // Background ring track
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 6)

                // Filled ring
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100.0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: score)

                // Emoji center
                Text(emoji)
                    .font(.system(size: 22))
            }
            .frame(width: 56, height: 56)

            // Score + label
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.8), value: score)
                    Text("/ 100")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                Text(scoreLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
