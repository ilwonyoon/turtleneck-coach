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
    let headPitch: CGFloat  // baseline head pitch from MediaPipe solvePnP
    let baselineFaceSize: CGFloat   // Face size at calibration time
    let forwardDepth: CGFloat  // baseline nose-shoulder Z-depth

    /// Decode with backward compatibility — headPitch/baselineFaceSize default to 0 if missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        earShoulderDistanceLeft = try c.decode(CGFloat.self, forKey: .earShoulderDistanceLeft)
        earShoulderDistanceRight = try c.decode(CGFloat.self, forKey: .earShoulderDistanceRight)
        eyeShoulderDistanceLeft = try c.decode(CGFloat.self, forKey: .eyeShoulderDistanceLeft)
        eyeShoulderDistanceRight = try c.decode(CGFloat.self, forKey: .eyeShoulderDistanceRight)
        headForwardRatio = try c.decode(CGFloat.self, forKey: .headForwardRatio)
        headTiltAngle = try c.decode(CGFloat.self, forKey: .headTiltAngle)
        neckEarAngle = try c.decode(CGFloat.self, forKey: .neckEarAngle)
        shoulderEvenness = try c.decode(CGFloat.self, forKey: .shoulderEvenness)
        earsWereVisible = try c.decode(Bool.self, forKey: .earsWereVisible)
        headPitch = try c.decodeIfPresent(CGFloat.self, forKey: .headPitch) ?? 0
        baselineFaceSize = try c.decodeIfPresent(CGFloat.self, forKey: .baselineFaceSize) ?? 0
        forwardDepth = try c.decodeIfPresent(CGFloat.self, forKey: .forwardDepth) ?? 0
    }

    init(
        earShoulderDistanceLeft: CGFloat,
        earShoulderDistanceRight: CGFloat,
        eyeShoulderDistanceLeft: CGFloat,
        eyeShoulderDistanceRight: CGFloat,
        headForwardRatio: CGFloat,
        headTiltAngle: CGFloat,
        neckEarAngle: CGFloat,
        shoulderEvenness: CGFloat,
        earsWereVisible: Bool,
        headPitch: CGFloat = 0,
        baselineFaceSize: CGFloat = 0,
        forwardDepth: CGFloat = 0
    ) {
        self.earShoulderDistanceLeft = earShoulderDistanceLeft
        self.earShoulderDistanceRight = earShoulderDistanceRight
        self.eyeShoulderDistanceLeft = eyeShoulderDistanceLeft
        self.eyeShoulderDistanceRight = eyeShoulderDistanceRight
        self.headForwardRatio = headForwardRatio
        self.headTiltAngle = headTiltAngle
        self.neckEarAngle = neckEarAngle
        self.shoulderEvenness = shoulderEvenness
        self.earsWereVisible = earsWereVisible
        self.headPitch = headPitch
        self.baselineFaceSize = baselineFaceSize
        self.forwardDepth = forwardDepth
    }
}

/// Result of a calibration attempt with validation feedback.
struct CalibrationResult {
    let data: CalibrationData?
    let isValid: Bool
    let message: String
    let measuredCVA: CGFloat
}
