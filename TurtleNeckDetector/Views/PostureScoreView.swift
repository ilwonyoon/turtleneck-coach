import SwiftUI

/// Posture score gauge (0-100) with emoji and color zones.
struct PostureScoreView: View {
    let score: Int
    let emoji: String

    private var scoreColor: Color {
        if score >= 75 { return .green }
        if score >= 50 { return .yellow }
        if score >= 25 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 8) {
            // Emoji + Score
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 28))
                Text("\(score)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.8), value: score)
                Text("/ 100")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Zone background
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.red.opacity(0.25))
                            .frame(width: geo.size.width * 0.25)
                        Rectangle().fill(Color.orange.opacity(0.2))
                            .frame(width: geo.size.width * 0.15)
                        Rectangle().fill(Color.yellow.opacity(0.15))
                            .frame(width: geo.size.width * 0.15)
                        Rectangle().fill(Color.green.opacity(0.2))
                            .frame(width: geo.size.width * 0.45)
                    }
                    .clipShape(Capsule())

                    // Needle
                    let position = min(max(CGFloat(score) / 100.0, 0), 1) * geo.size.width
                    Capsule()
                        .fill(.white)
                        .frame(width: 4, height: 18)
                        .shadow(color: .white.opacity(0.6), radius: 4)
                        .offset(x: position - 2)
                        .animation(.easeInOut(duration: 0.4), value: score)
                }
            }
            .frame(height: 22)
        }
    }
}
