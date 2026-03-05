import Foundation

/// Dynamic feedback messages and streak tracking.
/// Turtleneck Coach brand voice: firm but kind coach, short/clear/actionable, no medical claims.
struct FeedbackEngine {

    struct FeedbackMessage {
        let main: String
        let sub: String
    }

    // Good posture messages by duration threshold (seconds)
    private static let goodMessages: [(after: TimeInterval, main: String, sub: String)] = [
        (0,    "Good posture",  "Keep it here."),
        (30,   "30s streak",    "Nice work."),
        (60,   "1 min solid",   "Building the habit."),
        (120,  "2 min straight","Consistency wins."),
        (300,  "5 min in",      "Stretch your neck soon."),
        (600,  "10 min",        "Stand up. Move for 30 sec."),
        (1200, "20 min!",       "Go grab some water."),
        (1800, "30 min",        "Roll your shoulders back."),
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
    /// headYaw: absolute yaw in degrees (0 = facing camera). >15° = turned sideways.
    static func severityTip(
        for severity: Severity,
        headYaw: CGFloat = 0,
        classification: PostureClassification = .normal
    ) -> String {
        let absYaw = abs(headYaw)

        // Head turned sideways — override with rotation-specific message
        if absYaw > 15 {
            let direction = headYaw > 0 ? "left" : "right"
            if absYaw > 30 {
                return "Head turned far \(direction). Face your screen."
            }
            return "Head turned \(direction). Try to face forward."
        }

        if classification == .lookingDown {
            return "Chin up. Eyes to screen level."
        }

        switch severity {
        case .correction:
            return "Ears over shoulders."
        case .bad:
            return "Sit back. Open chest. Chin in."
        case .away:
            return "Tracking resumes when you're back."
        case .good:
            return "Right where you should be."
        }
    }
}
