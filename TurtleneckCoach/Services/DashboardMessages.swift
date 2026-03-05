import Foundation

struct DashboardMessage {
    let main: String
    let sub: String
}

enum TrendDirection {
    case declining
    case stable
    case improving
    case newUser
}

/// Famous quotes twisted for turtle neck humor.
/// Messages are selected based on daily good-posture percentage and weekly trend.
enum DashboardMessages {

    static func message(forProgress percent: Double, trend: TrendDirection) -> DashboardMessage {
        let pool: [DashboardMessage]
        switch (percent, trend) {
        case (_, .newUser):
            pool = newUser
        case (..<30, _):
            pool = bad
        case (30..<70, _):
            pool = okay
        default:
            pool = good
        }
        let index = Int.random(in: 0..<pool.count)
        return pool[index]
    }

    static let microWins: [String] = [
        "Neck check: nailed it!",
        "Turtle power!",
        "Shell yeah!",
        "Posture: locked in.",
        "Spine in line!",
        "Slow and steady wins.",
        "That's the stretch!",
        "Coach is proud.",
        "Chin tucked, crown up.",
        "One rep closer to freedom."
    ]

    // MARK: - Good (>= 70%)

    private static let good: [DashboardMessage] = [
        DashboardMessage(
            main: "I sat, I saw, I conquered.",
            sub: "— \"Julius Turtle\""
        ),
        DashboardMessage(
            main: "May the Force be with your C-spine.",
            sub: "— \"Obi-Wan Turtnobi\""
        ),
        DashboardMessage(
            main: "With great power comes great posture.",
            sub: "— \"Uncle Shell\""
        ),
        DashboardMessage(
            main: "Keep calm and chin up.",
            sub: "— \"Winston Turtchill\""
        ),
        DashboardMessage(
            main: "Houston, we no longer have a neck problem.",
            sub: "— \"Turtle Lovell\""
        ),
        DashboardMessage(
            main: "Here's looking at you, chin.",
            sub: "— \"Humphrey Turtgart\""
        ),
        DashboardMessage(
            main: "All's well that sits well.",
            sub: "— \"William Shelkspeare\""
        ),
        DashboardMessage(
            main: "Not all those who wander are lost.",
            sub: "— \"J.R.R. Turtkin\""
        ),
        DashboardMessage(
            main: "You had me at neutral spine.",
            sub: "— \"Jerry Turtguire\""
        ),
        DashboardMessage(
            main: "The only thing to fear is forward head itself.",
            sub: "— \"Franklin D. Turtlevelt\""
        ),
        DashboardMessage(
            main: "Sit like a turtle, stand like a tree.",
            sub: "— \"Muhammad Shelli\""
        ),
    ]

    // MARK: - Okay (30–70%)

    private static let okay: [DashboardMessage] = [
        DashboardMessage(
            main: "To slouch, or not to slouch?",
            sub: "— \"William Shelkspeare\""
        ),
        DashboardMessage(
            main: "Rome wasn't built in a day.",
            sub: "— \"Ancient Turtle Proverb\""
        ),
        DashboardMessage(
            main: "One does not simply doomscroll with neutral neck.",
            sub: "— \"Turtlemir\""
        ),
        DashboardMessage(
            main: "Winter is coming.",
            sub: "— \"Ned Turtk\""
        ),
        DashboardMessage(
            main: "May the odds be ever in your ergonomic favor.",
            sub: "— \"Effie Turtket\""
        ),
        DashboardMessage(
            main: "I'll be back...",
            sub: "— \"The Turtlenator\""
        ),
        DashboardMessage(
            main: "Ask not what your neck can do for your desk.",
            sub: "— \"John F. Turtledy\""
        ),
        DashboardMessage(
            main: "A journey of a thousand miles begins with one chin tuck.",
            sub: "— \"Lao Turtle\""
        ),
        DashboardMessage(
            main: "Keep your friends close and your monitor closer.",
            sub: "— \"Don Turtleone\""
        ),
        DashboardMessage(
            main: "Small sits lead to big shifts.",
            sub: "— \"Coach Turtle\""
        ),
    ]

    // MARK: - Bad (< 30%)

    private static let bad: [DashboardMessage] = [
        DashboardMessage(
            main: "Houston, we have a neck problem.",
            sub: "— \"Turtle Lovell\""
        ),
        DashboardMessage(
            main: "Your posture has left the chat.",
            sub: "— \"Turtle Messenger\""
        ),
        DashboardMessage(
            main: "Frankly, my neck, I do give a damn.",
            sub: "— \"Rhett Turtler\""
        ),
        DashboardMessage(
            main: "This is fine.",
            sub: "— \"Turtle in Flames Meme\""
        ),
        DashboardMessage(
            main: "Et tu, trapezius?",
            sub: "— \"Julius Turtle\""
        ),
        DashboardMessage(
            main: "Breaking news: local human becoming croissant.",
            sub: "— \"Turtle News Network\""
        ),
        DashboardMessage(
            main: "You miss 100% of the chin tucks you don't take.",
            sub: "— \"Wayne Turtsky\""
        ),
        DashboardMessage(
            main: "Keep scrolling and carry neck pain.",
            sub: "— \"British Turtle Proverb\""
        ),
        DashboardMessage(
            main: "The Turtling: Part II.",
            sub: "— \"Stephen Shellking\""
        ),
        DashboardMessage(
            main: "Your neck wasn't curved in a day.",
            sub: "— \"Ancient Turtle Proverb\""
        ),
    ]

    // MARK: - New User

    private static let newUser: [DashboardMessage] = [
        DashboardMessage(
            main: "Welcome to Turtleneck Coach.",
            sub: "— \"Coach Turtle\""
        ),
        DashboardMessage(
            main: "No shame. Just neck gains.",
            sub: "— \"Coach Turtle\""
        ),
        DashboardMessage(
            main: "First rule of Neck Club:",
            sub: "— \"Tyler Turtden\""
        ),
        DashboardMessage(
            main: "May the Force be with your desk setup.",
            sub: "— \"Obi-Wan Turtnobi\""
        ),
        DashboardMessage(
            main: "You're not broken.",
            sub: "— \"Dr. Turtle, PhD\""
        ),
        DashboardMessage(
            main: "Your spine called before you did.",
            sub: "— \"Turtle Helpdesk\""
        ),
        DashboardMessage(
            main: "Start where your neck is.",
            sub: "— \"Arthur Turtashe\""
        ),
    ]
}
