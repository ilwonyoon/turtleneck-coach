import Foundation

/// Immutable baseline posture measurements persisted to UserDefaults.
/// Port of Python CalibrationData from calibration.py.
struct CalibrationData: Codable {
    let earShoulderDistanceLeft: CGFloat
    let earShoulderDistanceRight: CGFloat
    let eyeShoulderDistanceLeft: CGFloat
    let eyeShoulderDistanceRight: CGFloat
    let headForwardRatio: CGFloat
    let headTiltAngle: CGFloat
    let neckEarAngle: CGFloat  // baseline CVA proxy
    let shoulderEvenness: CGFloat
    let earsWereVisible: Bool
}

/// Result of a calibration attempt with validation feedback.
struct CalibrationResult {
    let data: CalibrationData?
    let isValid: Bool
    let message: String
    let measuredCVA: CGFloat
}
