import Foundation

/// Classifies posture deviation type using pitch and depth proxy signals.
struct PostureClassifier {

    /// Classify whether a CVA drop is FHP or neck flexion.
    /// - Parameters:
    ///   - currentPitch: Current head pitch in radians
    ///   - baselinePitch: Calibration baseline pitch in radians
    ///   - currentFaceSize: Current normalized face size (0-1)
    ///   - baselineFaceSize: Calibration baseline face size (0-1)
    ///   - cvaDrop: How much CVA dropped from baseline (positive = worse)
    ///   - yawDegrees: Current absolute yaw in degrees
    /// - Returns: PostureClassification
    static func classify(
        currentPitch: CGFloat,
        baselinePitch: CGFloat,
        currentFaceSize: CGFloat,
        baselineFaceSize: CGFloat,
        cvaDrop: CGFloat,
        yawDegrees: CGFloat
    ) -> PostureClassification {
        // Can't classify with high yaw or missing data
        guard yawDegrees < 20 else { return .unknown }
        guard baselineFaceSize > 0 else { return .unknown }

        // No significant CVA drop — posture is fine
        guard cvaDrop > 1.5 else { return .normal }

        // Compute relative changes
        // Vision face pitch is in radians but can be large absolute values;
        // use raw difference without radian-to-degree conversion since we
        // calibrate relative to baseline.
        let pitchDelta = currentPitch - baselinePitch  // negative = looking more downward for Vision
        let absPitchDelta = abs(pitchDelta)
        let faceSizeChange = baselineFaceSize > 0
            ? (currentFaceSize - baselineFaceSize) / baselineFaceSize
            : 0

        // Vision pitch: values like -6 to -9; a delta of 0.3+ is meaningful
        let strongPitchDown = absPitchDelta > 0.5
        let mildPitchDown = absPitchDelta > 0.2
        let faceGrowing = faceSizeChange > 0.04        // head moving toward camera

        if strongPitchDown && !faceGrowing {
            return .lookingDown
        } else if !mildPitchDown && faceGrowing {
            return .forwardHead
        } else if strongPitchDown && faceGrowing {
            return .mixed
        } else if mildPitchDown && !faceGrowing {
            return .lookingDown
        } else {
            return .forwardHead  // default: CVA dropped without clear pitch = FHP
        }
    }
}
