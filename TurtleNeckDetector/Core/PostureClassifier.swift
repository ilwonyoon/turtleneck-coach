import Foundation

/// Tunable FHP detection parameters (adjustable via debug sliders).
final class FHPTuning: ObservableObject {
    static let shared = FHPTuning()

    /// Face shrink threshold: faceSize drop % to trigger FHP (negative, e.g. -0.03 = -3%)
    @Published var faceShrinkThreshold: Double = -0.03

    /// Depth penalty scale: how much depth increase penalizes CVA (higher = more penalty)
    @Published var depthPenaltyScale: Double = 180.0

    /// Pitch gate: if pitch drops more than this (degrees), classify as lookingDown not FHP
    @Published var pitchGateDegrees: Double = 5.0
}

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
        yawDegrees: CGFloat,
        forwardDepth: CGFloat = 0,
        baselineForwardDepth: CGFloat = 0
    ) -> PostureClassification {
        // Can't classify with high yaw or missing data
        guard yawDegrees < 20 else { return .unknown }
        guard baselineFaceSize > 0 else { return .unknown }

        let depthIncrease = forwardDepth - baselineForwardDepth
        let faceSizeChange = baselineFaceSize > 0
            ? (currentFaceSize - baselineFaceSize) / baselineFaceSize
            : CGFloat(0)
        // Priority 1: Detect forward head posture aggressively.
        // Priority 2: Looking down handled via notification suppression, not classification.
        //
        // FHP signals (any one triggers):
        //   a) Face shrinking > 6% (head moved forward, appears smaller)
        //   b) Depth increased > 0.04 (nose moved forward of shoulders in Z)
        //   c) cvaDrop negative + face shrinking (pitch masked the CVA drop)
        let tuning = FHPTuning.shared
        let pitchDrop = baselinePitch - currentPitch  // positive = head tilted more down
        let isLookingDown = pitchDrop > tuning.pitchGateDegrees

        let faceShrinking = faceSizeChange < tuning.faceShrinkThreshold
        let depthUp = baselineForwardDepth > 0 && depthIncrease > 0.04

        // If face is shrinking or depth increased, it's FHP — unless pitch gate says looking down
        if (faceShrinking || depthUp) && !isLookingDown {
            return .forwardHead
        }

        if cvaDrop < -3.0 && faceSizeChange < tuning.faceShrinkThreshold && !isLookingDown {
            return .forwardHead
        }

        // No significant deviation
        guard cvaDrop > 1.5 else { return .normal }

        // CVA dropped. Classify by pitch.
        let pitchDelta = currentPitch - baselinePitch
        let absPitchDelta = abs(pitchDelta)
        let strongPitchDown = absPitchDelta > 0.5
        let mildPitchDown = absPitchDelta > 0.2
        let faceGrowing = faceSizeChange > 0.04

        if strongPitchDown && !faceGrowing {
            return .lookingDown
        } else if !mildPitchDown && faceGrowing {
            return .forwardHead
        } else if strongPitchDown && faceGrowing {
            return .mixed
        } else if mildPitchDown && !faceGrowing {
            return .lookingDown
        } else {
            return .forwardHead
        }
    }
}
