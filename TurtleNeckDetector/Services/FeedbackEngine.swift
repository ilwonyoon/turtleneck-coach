import Foundation

/// Dynamic feedback messages and streak tracking.
/// Port of goodMessages/warningTips from web_app.py JS.
struct FeedbackEngine {

    struct FeedbackMessage {
        let main: String
        let sub: String
    }

    // Good posture messages by duration threshold (seconds)
    private static let goodMessages: [(after: TimeInterval, main: String, sub: String)] = [
        (0,    "Good posture!",          "Keep it up"),
        (30,   "Nice form!",             "30 seconds of good posture"),
        (60,   "Great job!",             "1 minute streak going strong"),
        (120,  "Excellent!",             "2 minutes - your neck thanks you"),
        (300,  "Posture champion!",      "5 min streak! Take a stretch break soon"),
        (600,  "Amazing discipline!",    "10 min! Consider standing up briefly"),
        (1200, "Incredible focus!",      "20 min - time for a quick break?"),
        (1800, "You're on fire!",        "30 min streak! Stand and stretch"),
    ]

    private static let warningTips = [
        "Try pulling your chin back slightly",
        "Imagine a string pulling the top of your head up",
        "Roll your shoulders back and down",
        "Check: are your ears above your shoulders?",
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
            return "Pull your chin back and sit up tall"
        case .moderate:
            return "Your head is significantly forward - sit back and realign"
        case .severe:
            return "Stop and take a break! Stand up and do neck stretches"
        case .good:
            return "Keep it up!"
        }
    }
}
