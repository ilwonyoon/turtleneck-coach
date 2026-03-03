import Foundation

/// Dynamic feedback messages and streak tracking.
/// PT Turtle brand voice: firm but kind coach, short/clear/actionable, no medical claims.
struct FeedbackEngine {

    struct FeedbackMessage {
        let main: String
        let sub: String
    }

    // Good posture messages by duration threshold (seconds)
    private static let goodMessages: [(after: TimeInterval, main: String, sub: String)] = [
        (0,    "Looking good.",           "Nice and tall. Keep it here."),
        (30,   "30 seconds strong.",      "Your neck says thank you."),
        (60,   "One minute, solid.",      "This is building a habit."),
        (120,  "Two minutes straight.",   "Consistency beats perfection."),
        (300,  "Five minutes in.",        "Nice run. Stretch your neck soon."),
        (600,  "Ten solid minutes.",      "Stand up and move for 30 seconds."),
        (1200, "Twenty minutes. Respect.", "Walk to the kitchen. Get water."),
        (1800, "Half hour. Impressive.",  "Time to stand. Roll your shoulders back."),
    ]

    private static let warningTips = [
        "Tuck your chin back gently.",
        "Sit tall. Crown of your head toward the ceiling.",
        "Shoulders back and down. Hold three seconds.",
        "Quick check: ears over shoulders?",
    ]

    /// Get the appropriate good-posture message for the given streak duration.
    static func goodMessage(forDuration seconds: TimeInterval) -> FeedbackMessage {
        var msg = goodMessages[0]
        for m in goodMessages where seconds >= m.after {
            msg = m
        }
        return FeedbackMessage(main: msg.main, sub: msg.sub)
    }

    /// Get a rotating warning tip.
    static func warningTip(index: Int) -> String {
        warningTips[index % warningTips.count]
    }

    /// Format a time duration for display.
    static func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    /// Severity-specific tips shown in the UI.
    static func severityTip(for severity: Severity) -> String {
        switch severity {
        case .mild:
            return "Head's drifting forward. Tuck your chin back."
        case .moderate:
            return "Your neck is working hard right now. Sit back. Chin in."
        case .severe:
            return "Time to reset. Stand up and roll your neck gently."
        case .good:
            return "Right where you should be."
        }
    }
}
