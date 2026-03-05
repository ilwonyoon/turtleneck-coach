import Foundation

/// Tunable FHP detection parameters (adjustable via debug sliders).
final class FHPTuning: ObservableObject {
    static let shared = FHPTuning()

    /// Face shrink threshold: faceSize drop % to trigger FHP (negative, e.g. -0.06 = -6%)
    /// Data shows: normal movement -0~3%, looking down -1~3%, FHP -10~15%
    @Published var faceShrinkThreshold: Double = -0.06

    /// Depth penalty scale: how much depth increase penalizes CVA (higher = more penalty)
    @Published var depthPenaltyScale: Double = 180.0

    /// Pitch gate: if pitch drops more than this (degrees), classify as lookingDown not FHP
    @Published var pitchGateDegrees: Double = 5.0

    /// Iris gaze threshold: normalized offset above which eyes are considered "looking down"
    @Published var irisGazeThreshold: Double = 0.25
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
        baselineForwardDepth: CGFloat = 0,
        irisGazeOffset: CGFloat = 0,
        baselineIrisGaze: CGFloat = 0
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

        let faceShrinking = faceSizeChange < tuning.faceShrinkThreshold

        // Key discriminator from data analysis:
        //   FHP (거북목): faceSize drops significantly (-10~15%) — head moves forward, face appears smaller
        //   Looking down (고개 숙임): faceSize barely changes (-1~3%) — head tilts but stays in place
        //
        // Face shrink magnitude is the most reliable separator.
        // Iris gaze and pitch are similar between the two postures.
        let significantFaceShrink = faceSizeChange < -0.08  // >8% shrink = confident FHP
        let depthUp = baselineForwardDepth > 0 && depthIncrease > 0.06

        // FHP: large face shrink OR significant depth increase → head translated forward
        if significantFaceShrink || depthUp {
            return .forwardHead
        }

        // Moderate face shrink (-6~8%) — ambiguous zone
        if faceShrinking {
            // With significant pitch drop → looking down (head tilting, not translating)
            if pitchDrop > tuning.pitchGateDegrees {
                return .lookingDown
            }
            // Without pitch drop → mild FHP (head drifting forward)
            return .forwardHead
        }

        if cvaDrop < -3.0 && faceSizeChange < tuning.faceShrinkThreshold {
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
