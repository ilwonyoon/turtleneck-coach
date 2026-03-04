import Foundation

/// Posture severity classification.
/// Raw values keep legacy strings for backward compatibility with saved settings.
enum Severity: String, Comparable {
    case good = "good"
    case correction = "mild"
    case bad = "moderate"
    case away = "severe"

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

/// Current posture detection state, updated each analysis cycle.
struct PostureState {
    var badPostureStart: Date?
    var isTurtleNeck: Bool
    var deviationScore: CGFloat
    var usingFallback: Bool
    var severity: Severity
    var currentCVA: CGFloat
    var baselineCVA: CGFloat

    static let initial = PostureState(
        badPostureStart: nil,
        isTurtleNeck: false,
        deviationScore: 0,
        usingFallback: false,
        severity: .good,
        currentCVA: 0,
        baselineCVA: 0
    )
}
