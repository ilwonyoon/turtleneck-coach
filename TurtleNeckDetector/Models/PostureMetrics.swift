import Foundation

/// Immutable posture measurement from a single frame analysis.
/// Port of Python PostureMetrics dataclass from pose_detector.py.
struct PostureMetrics {
    let earShoulderDistanceLeft: CGFloat
    let earShoulderDistanceRight: CGFloat
    let eyeShoulderDistanceLeft: CGFloat
    let eyeShoulderDistanceRight: CGFloat
    let headForwardRatio: CGFloat
    let headTiltAngle: CGFloat
    let neckEarAngle: CGFloat  // CVA proxy: angle from neck to ear relative to vertical
    let shoulderEvenness: CGFloat
    let earsVisible: Bool
    let landmarksDetected: Bool

    static let empty = PostureMetrics(
        earShoulderDistanceLeft: 0,
        earShoulderDistanceRight: 0,
        eyeShoulderDistanceLeft: 0,
        eyeShoulderDistanceRight: 0,
        headForwardRatio: 0,
        headTiltAngle: 0,
        neckEarAngle: 0,
        shoulderEvenness: 0,
        earsVisible: false,
        landmarksDetected: false
    )
}
