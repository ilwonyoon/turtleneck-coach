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
        HStack(spacing: 14) { // DS: one-off
            // Activity Ring with emoji
            ZStack {
                // Background ring track
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: DS.Size.scoreStroke)

                // Filled ring
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100.0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: DS.Size.scoreStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: score)

                // Emoji center
                Text(emoji)
                    .font(DS.Font.emoji)
            }
            .frame(width: DS.Size.scoreRing, height: DS.Size.scoreRing)

            // Score + label
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score)")
                        .font(DS.Font.scoreLg)
                        .foregroundColor(scoreColor)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.8), value: score)
                    Text("/ 100")
                        .font(DS.Font.callout)
                        .foregroundColor(.secondary)
                }
                Text(scoreLabel)
                    .font(DS.Font.sysSubhead)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
