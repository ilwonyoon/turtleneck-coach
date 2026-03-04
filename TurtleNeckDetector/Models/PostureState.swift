import Foundation

/// Posture severity classification.
/// Raw values keep legacy strings for backward compatibility with saved settings.
enum Severity: String, CaseIterable, Comparable {
    case good = "good"
    case correction = "mild"
    case bad = "moderate"
    case away = "severe"

    var displayName: String {
        switch self {
        case .good: return "Great"
        case .correction: return "Adjust"
        case .bad: return "Reset"
        case .away: return "Break"
        }
    }

    private var order: Int {
        switch self {
        case .good: return 0
        case .correction: return 1
        case .bad: return 2
        case .away: return 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.order < rhs.order
    }
}

/// Classification of the type of posture deviation detected.
enum PostureClassification: String {
    case normal          // Good posture
    case forwardHead     // True FHP: head forward, minimal pitch change
    case lookingDown     // Neck flexion: pitch increased significantly, head not forward
    case mixed           // Both signals present
    case unknown         // Insufficient data or yaw too high
}

/// Current posture detection state, updated each analysis cycle.
struct PostureState {
    var badPostureStart: Date?
    var isTurtleNeck: Bool
    var deviationScore: CGFloat
    var usingFallback: Bool
    var severity: Severity
    var classification: PostureClassification
    var currentCVA: CGFloat
    var baselineCVA: CGFloat

    static let initial = PostureState(
        badPostureStart: nil,
        isTurtleNeck: false,
        deviationScore: 0,
        usingFallback: false,
        severity: .good,
        classification: .normal,
        currentCVA: 0,
        baselineCVA: 0
    )
}
