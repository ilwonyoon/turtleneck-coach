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

    enum EyeLevelNarrowClassification: String {
        case forwardHead
        case lookingDown
        case inconclusive
    }

    struct EyeLevelNarrowResult {
        let classification: EyeLevelNarrowClassification
        let confidence: CGFloat
        let forwardHeadEvidence: CGFloat
        let lookingDownEvidence: CGFloat
    }

    /// Log-only helper for eye-level setups where the main ambiguity is
    /// forward head translation vs downward-looking posture.
    ///
    /// This helper is intentionally narrow:
    /// - It does not replace `classify(...)`
    /// - It assumes an eye-level camera relation
    /// - It only returns a lightweight directional result with confidence
    static func classifyEyeLevelForwardHeadVsLookingDown(
        cvaDrop: CGFloat,
        pitchDrop: CGFloat,
        faceSizeChange: CGFloat,
        depthIncrease: CGFloat,
        yawDegrees: CGFloat,
        irisGazeOffset: CGFloat
    ) -> EyeLevelNarrowResult {
        guard yawDegrees < 20 else {
            return EyeLevelNarrowResult(
                classification: .inconclusive,
                confidence: 0,
                forwardHeadEvidence: 0,
                lookingDownEvidence: 0
            )
        }

        let tuning = FHPTuning.shared

        func clamp01(_ value: CGFloat) -> CGFloat {
            min(1, max(0, value))
        }

        let cvaSignal = clamp01((cvaDrop - 2.0) / 8.0)
        let pitchSignal = clamp01((pitchDrop - 2.0) / max(CGFloat(tuning.pitchGateDegrees), 1.0))
        let depthSignal = clamp01(depthIncrease / 0.05)
        let gazeSignal = clamp01(abs(irisGazeOffset) / max(CGFloat(tuning.irisGazeThreshold), 0.01))
        let faceShrinkSignal = clamp01((-faceSizeChange - 0.02) / 0.08)
        let stableFaceSignal = clamp01(1.0 - abs(faceSizeChange) / 0.05)
        let weakTranslationSignal = clamp01(1.0 - faceShrinkSignal)
        let weakDepthSignal = clamp01(1.0 - depthSignal)
        let maxTranslationSignal = max(faceShrinkSignal, depthSignal)

        let goodGuard =
            cvaDrop < 3.5 &&
            pitchDrop < 4.0 &&
            abs(faceSizeChange) < 0.03 &&
            depthIncrease < 0.025 &&
            abs(irisGazeOffset) < 0.18
        if goodGuard {
            return EyeLevelNarrowResult(
                classification: .inconclusive,
                confidence: 0,
                forwardHeadEvidence: 0,
                lookingDownEvidence: 0
            )
        }

        let forwardHeadEvidence =
            cvaSignal * 0.40 +
            depthSignal * 0.30 +
            faceShrinkSignal * 0.25 +
            (1.0 - pitchSignal) * 0.05

        let lookingDownEvidence =
            pitchSignal * 0.55 +
            gazeSignal * 0.15 +
            weakTranslationSignal * 0.15 +
            stableFaceSignal * 0.10 +
            weakDepthSignal * 0.05

        let lowMeaningfulDeviation = cvaDrop < 4.5 && maxTranslationSignal < 0.35 && pitchSignal < 0.70
        if lowMeaningfulDeviation {
            return EyeLevelNarrowResult(
                classification: .inconclusive,
                confidence: clamp01(max(forwardHeadEvidence, lookingDownEvidence) * 0.25),
                forwardHeadEvidence: forwardHeadEvidence,
                lookingDownEvidence: lookingDownEvidence
            )
        }

        if cvaSignal > 0.30,
           pitchSignal > 0.80,
           faceShrinkSignal < 0.25,
           depthSignal < 0.25,
           pitchSignal - maxTranslationSignal > 0.35 {
            return EyeLevelNarrowResult(
                classification: .lookingDown,
                confidence: clamp01(lookingDownEvidence - forwardHeadEvidence + 0.15),
                forwardHeadEvidence: forwardHeadEvidence,
                lookingDownEvidence: lookingDownEvidence
            )
        }

        if faceShrinkSignal > 0.55 || depthSignal > 0.55 {
            return EyeLevelNarrowResult(
                classification: .forwardHead,
                confidence: clamp01(forwardHeadEvidence - lookingDownEvidence + 0.15),
                forwardHeadEvidence: forwardHeadEvidence,
                lookingDownEvidence: lookingDownEvidence
            )
        }

        let competingSignals = cvaSignal > 0.40 && pitchSignal > 0.60
        let ambiguousTranslation = depthSignal < 0.55 && faceShrinkSignal < 0.55
        if competingSignals && ambiguousTranslation {
            return EyeLevelNarrowResult(
                classification: .inconclusive,
                confidence: clamp01(abs(forwardHeadEvidence - lookingDownEvidence) * 0.5),
                forwardHeadEvidence: forwardHeadEvidence,
                lookingDownEvidence: lookingDownEvidence
            )
        }

        let bestEvidence = max(forwardHeadEvidence, lookingDownEvidence)
        let confidence = clamp01(bestEvidence - min(forwardHeadEvidence, lookingDownEvidence))

        if bestEvidence < 0.45 || confidence < 0.15 {
            return EyeLevelNarrowResult(
                classification: .inconclusive,
                confidence: confidence,
                forwardHeadEvidence: forwardHeadEvidence,
                lookingDownEvidence: lookingDownEvidence
            )
        }

        return EyeLevelNarrowResult(
            classification: forwardHeadEvidence >= lookingDownEvidence ? .forwardHead : .lookingDown,
            confidence: confidence,
            forwardHeadEvidence: forwardHeadEvidence,
            lookingDownEvidence: lookingDownEvidence
        )
    }

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
