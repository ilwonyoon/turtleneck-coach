import Foundation

enum SensitivityMode: String, CaseIterable {
    case relaxed
    case balanced
    case strict

    static let storageKey = "sensitivityMode"
    static let defaultMode: SensitivityMode = .balanced

    var displayName: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .balanced: return "Balanced"
        case .strict: return "Strict"
        }
    }

    var goodThreshold: Int {
        switch self {
        case .relaxed: return 70
        case .balanced: return 75
        case .strict: return 82
        }
    }

    var correctionThreshold: Int {
        goodThreshold - 20
    }

    var badThreshold: Int {
        goodThreshold - 40
    }
}

/// Posture evaluation engine.
/// Port of Python detector.py - evaluates posture against calibration baseline.
struct PostureAnalyzer {

    // Deviation thresholds from baseline (from detector.py)
    static let forwardRatioThreshold: CGFloat = 0.15
    static let earShoulderThreshold: CGFloat = 0.20
    static let eyeShoulderThreshold: CGFloat = 0.18
    static let sideViewEarThreshold: CGFloat = 0.15
    static let sustainedDurationSec: TimeInterval = 5.0

    static var currentSensitivityMode: SensitivityMode {
        let rawValue = UserDefaults.standard.string(forKey: SensitivityMode.storageKey)
        return SensitivityMode(rawValue: rawValue ?? "") ?? .balanced
    }

    // Score severity thresholds based on sensitivity mode.
    static var scoreGoodThreshold: Int {
        currentSensitivityMode.goodThreshold
    }

    static var scoreCorrectionThreshold: Int {
        currentSensitivityMode.correctionThreshold
    }

    static var scoreBadThreshold: Int {
        currentSensitivityMode.badThreshold
    }

    /// Evaluate current posture metrics against calibration baseline.
    /// Returns a new PostureState (immutable pattern - creates new state each call).
    static func evaluate(
        metrics: PostureMetrics,
        baseline: CalibrationData,
        previousState: PostureState,
        cameraPosition: CameraPosition,
        yawDegrees: CGFloat = 0,
        sensitivityMode: SensitivityMode = currentSensitivityMode
    ) -> PostureState {
        guard metrics.landmarksDetected else {
            return PostureState(
                badPostureStart: previousState.badPostureStart,
                isTurtleNeck: false,
                deviationScore: 0,
                usingFallback: previousState.usingFallback,
                severity: .good,
                classification: .unknown,
                currentCVA: 0,
                baselineCVA: baseline.neckEarAngle,
                score: 90
            )
        }

        let cvaDrop = baseline.neckEarAngle - metrics.neckEarAngle
        let classification = PostureClassifier.classify(
            currentPitch: metrics.headPitch,
            baselinePitch: baseline.headPitch,
            currentFaceSize: metrics.faceSizeNormalized,
            baselineFaceSize: baseline.baselineFaceSize,
            cvaDrop: cvaDrop,
            yawDegrees: abs(yawDegrees),
            forwardDepth: metrics.forwardDepth,
            baselineForwardDepth: baseline.forwardDepth,
            irisGazeOffset: metrics.irisGazeOffset,
            baselineIrisGaze: baseline.irisGazeOffset
        )
        let eyeLevelDebug = debugEyeLevelClassification(
            metrics: metrics,
            baseline: baseline,
            cameraPosition: cameraPosition,
            yawDegrees: abs(yawDegrees)
        )

        let adjustedCVA: CGFloat
        if classification == .lookingDown {
            let drop = baseline.neckEarAngle - metrics.neckEarAngle
            adjustedCVA = metrics.neckEarAngle + drop * 0.5  // recover 50% of CVA drop
        } else {
            adjustedCVA = metrics.neckEarAngle
        }

        let useFallback = !metrics.earsVisible

        // Compute relative score (camera-invariant)
        let computedScore: Int
        let deviationValue: CGFloat

        if useFallback {
            // Face fallback: use CVA-only relative score
            computedScore = relativeScore(currentCVA: adjustedCVA, baselineCVA: baseline.neckEarAngle)
            let effectiveCVADrop = baseline.neckEarAngle - adjustedCVA
            deviationValue = baseline.neckEarAngle > 1e-6 ? max(0, effectiveCVADrop / baseline.neckEarAngle) : 0.0
        } else {
            // Body pose: composite relative score with auxiliary signals
            computedScore = compositeRelativeScore(
                currentCVA: adjustedCVA, baselineCVA: baseline.neckEarAngle,
                currentPitch: metrics.headPitch, baselinePitch: baseline.headPitch,
                currentFaceSize: metrics.faceSizeNormalized, baselineFaceSize: baseline.baselineFaceSize,
                currentForwardDepth: metrics.forwardDepth, baselineForwardDepth: baseline.forwardDepth,
                classification: classification
            )
            let forwardDeviation = relativeChange(
                baseline: baseline.headForwardRatio,
                current: metrics.headForwardRatio
            )
            if cameraPosition.isSideView {
                let vertScore = evaluateSideView(
                    metrics: metrics, baseline: baseline,
                    cameraPosition: cameraPosition, useFallback: useFallback
                )
                deviationValue = vertScore + max(0, forwardDeviation) * 0.3
            } else {
                let vertScore = evaluateCenterView(
                    metrics: metrics, baseline: baseline, useFallback: useFallback
                )
                deviationValue = vertScore + max(0, forwardDeviation)
            }
        }

        let severity = classifySeverity(score: computedScore, mode: sensitivityMode)

        #if DEBUG
        let pitchDelta = metrics.headPitch - baseline.headPitch
        let pitchDrop = baseline.headPitch - metrics.headPitch
        let fsc = baseline.baselineFaceSize > 0 ? (metrics.faceSizeNormalized - baseline.baselineFaceSize) / baseline.baselineFaceSize : 0
        let depthIncrease = metrics.forwardDepth - baseline.forwardDepth
        let irisDelta = metrics.irisGazeOffset - baseline.irisGazeOffset
        var debugLine = String(format: "[EVAL] rawCVA=%.1f adj=%.1f base=%.1f class=%@ relScore=%d sev=%@ yaw=%.1f pitchΔ=%.2f faceΔ=%.1f%%",
            metrics.neckEarAngle, adjustedCVA, baseline.neckEarAngle,
            classification.rawValue, computedScore, severity.rawValue,
            yawDegrees, pitchDelta, fsc * 100)
        if let eyeLevelDebug {
            debugLine += String(
                format: " eye=active eyeClass=%@ eyeConf=%.2f eyeFwd=%.2f eyeDown=%.2f eyePitchDrop=%.2f depthΔ=%.3f irisΔ=%.3f",
                eyeLevelDebug.classification.rawValue,
                eyeLevelDebug.confidence,
                eyeLevelDebug.forwardHeadEvidence,
                eyeLevelDebug.lookingDownEvidence,
                pitchDrop,
                depthIncrease,
                irisDelta
            )
        } else {
            debugLine += " eye=skip"
        }
        DebugLogWriter.append(debugLine + "\n")
        #endif

        let isCurrentlyBad = severity != .good
        let now = Date()

        if isCurrentlyBad {
            let start = previousState.badPostureStart ?? now
            let duration = now.timeIntervalSince(start)
            let isTurtle = duration >= Self.sustainedDurationSec
            return PostureState(
                badPostureStart: start,
                isTurtleNeck: isTurtle,
                deviationScore: deviationValue,
                usingFallback: useFallback,
                severity: severity,
                classification: classification,
                currentCVA: adjustedCVA,
                baselineCVA: baseline.neckEarAngle,
                score: computedScore
            )
        }

        return PostureState(
            badPostureStart: nil,
            isTurtleNeck: false,
            deviationScore: deviationValue,
            usingFallback: useFallback,
            severity: severity,
            classification: classification,
            currentCVA: adjustedCVA,
            baselineCVA: baseline.neckEarAngle,
            score: computedScore
        )
    }

    // MARK: - Relative Scoring (camera-invariant)

    /// Convert CVA deviation from baseline to a 0-100 score.
    /// Uses absolute deviation — any direction away from baseline reduces score.
    /// 0% deviation = 95, ~15% = ~72, ~30% = ~50, 50%+ = ~20.
    static func relativeScore(currentCVA: CGFloat, baselineCVA: CGFloat) -> Int {
        guard baselineCVA > 1e-6 else { return 50 }
        let deviation = abs(baselineCVA - currentCVA) / baselineCVA
        let score = 95.0 - deviation * 150.0
        return Int(round(min(98, max(2, score))))
    }

    /// Fuse multiple relative signals into a single 0-100 score.
    /// pitchDrop is the primary penalty driver for FHP (universal across all monitor angles).
    /// Target curve: pitchDrop 3.5° → ~80, 5.0° → ~65, 7.0° → ~45
    static func compositeRelativeScore(
        currentCVA: CGFloat, baselineCVA: CGFloat,
        currentPitch: CGFloat, baselinePitch: CGFloat,
        currentFaceSize: CGFloat, baselineFaceSize: CGFloat,
        currentForwardDepth: CGFloat = 0,
        baselineForwardDepth: CGFloat = 0,
        classification: PostureClassification
    ) -> Int {
        let cvaScore = relativeScore(currentCVA: currentCVA, baselineCVA: baselineCVA)
        let pitchDrop = max(0, baselinePitch - currentPitch)
        let faceSizeChange = baselineFaceSize > 0 ? (currentFaceSize - baselineFaceSize) / baselineFaceSize : 0
        let depthIncrease = currentForwardDepth - baselineForwardDepth

        var composite = CGFloat(cvaScore)

        if classification == .forwardHead {
            // pitchDrop-primary penalty curve:
            //   pitchDrop 3.5° → penalty ~15 (score ~80 from baseline 95)
            //   pitchDrop 5.0° → penalty ~30 (score ~65)
            //   pitchDrop 7.0° → penalty ~50 (score ~45)
            // Formula: 10 * (pitchDrop - 1.5) for pitchDrop > 1.5°
            let pitchDropPenalty = max(0, (pitchDrop - 1.5) * 10.0)

            // Auxiliary penalties (secondary, additive)
            let faceShrinkPenalty = min(8.0, max(0, (-faceSizeChange) - 0.03) * 60.0)
            let depthPenalty = min(6.0, max(0, depthIncrease) * 60.0)

            composite -= (pitchDropPenalty + faceShrinkPenalty + depthPenalty)
        }

        // lookingDown: mild penalty from CVA score only, no additional penalty
        // (accepting some false positives as agreed — catching FHP is priority)

        return Int(round(min(98, max(2, composite))))
    }

    static func debugEyeLevelClassification(
        metrics: PostureMetrics,
        baseline: CalibrationData,
        cameraPosition: CameraPosition,
        yawDegrees: CGFloat
    ) -> PostureClassifier.EyeLevelNarrowResult? {
        guard !cameraPosition.isSideView else { return nil }
        guard yawDegrees < 20 else { return nil }
        guard baseline.baselineFaceSize > 0.0001 else { return nil }
        guard metrics.landmarksDetected else { return nil }

        let cvaDrop = baseline.neckEarAngle - metrics.neckEarAngle
        let pitchDrop = baseline.headPitch - metrics.headPitch
        let faceSizeChange = (metrics.faceSizeNormalized - baseline.baselineFaceSize) / baseline.baselineFaceSize
        let depthIncrease = metrics.forwardDepth - baseline.forwardDepth
        let irisDelta = metrics.irisGazeOffset - baseline.irisGazeOffset

        return PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: cvaDrop,
            pitchDrop: pitchDrop,
            faceSizeChange: faceSizeChange,
            depthIncrease: depthIncrease,
            yawDegrees: yawDegrees,
            irisGazeOffset: irisDelta
        )
    }

    // MARK: - Severity Classification

    static func classifySeverity(
        score: Int,
        mode: SensitivityMode = currentSensitivityMode
    ) -> Severity {
        if score >= mode.goodThreshold { return .good }
        if score >= mode.correctionThreshold { return .correction }
        if score >= mode.badThreshold { return .bad }
        return .away
    }

    // MARK: - Center View Evaluation

    private static func evaluateCenterView(
        metrics: PostureMetrics,
        baseline: CalibrationData,
        useFallback: Bool
    ) -> CGFloat {
        if !useFallback {
            let avgBaseline = (baseline.earShoulderDistanceLeft + baseline.earShoulderDistanceRight) / 2
            let avgCurrent = (metrics.earShoulderDistanceLeft + metrics.earShoulderDistanceRight) / 2
            let deviation = relativeChange(baseline: avgBaseline, current: avgCurrent)
            return max(0, -deviation)
        } else {
            let avgBaseline = (baseline.eyeShoulderDistanceLeft + baseline.eyeShoulderDistanceRight) / 2
            let avgCurrent = (metrics.eyeShoulderDistanceLeft + metrics.eyeShoulderDistanceRight) / 2
            let deviation = relativeChange(baseline: avgBaseline, current: avgCurrent)
            return max(0, -deviation)
        }
    }

    // MARK: - Side View Evaluation

    private static func evaluateSideView(
        metrics: PostureMetrics,
        baseline: CalibrationData,
        cameraPosition: CameraPosition,
        useFallback: Bool
    ) -> CGFloat {
        let primary = cameraPosition.primarySide

        if !useFallback {
            let bl: CGFloat
            let cur: CGFloat
            switch primary {
            case "left":
                bl = baseline.earShoulderDistanceLeft
                cur = metrics.earShoulderDistanceLeft
            case "right":
                bl = baseline.earShoulderDistanceRight
                cur = metrics.earShoulderDistanceRight
            default:
                bl = (baseline.earShoulderDistanceLeft + baseline.earShoulderDistanceRight) / 2
                cur = (metrics.earShoulderDistanceLeft + metrics.earShoulderDistanceRight) / 2
            }
            let deviation = relativeChange(baseline: bl, current: cur)
            return max(0, -deviation)
        } else {
            let bl: CGFloat
            let cur: CGFloat
            switch primary {
            case "left":
                bl = baseline.eyeShoulderDistanceLeft
                cur = metrics.eyeShoulderDistanceLeft
            case "right":
                bl = baseline.eyeShoulderDistanceRight
                cur = metrics.eyeShoulderDistanceRight
            default:
                bl = (baseline.eyeShoulderDistanceLeft + baseline.eyeShoulderDistanceRight) / 2
                cur = (metrics.eyeShoulderDistanceLeft + metrics.eyeShoulderDistanceRight) / 2
            }
            let deviation = relativeChange(baseline: bl, current: cur)
            return max(0, -deviation)
        }
    }

    // MARK: - Score Mapping

    /// Map posture score to emoji using the 4-zone posture model.
    static func scoreToEmoji(
        _ score: Int,
        mode: SensitivityMode = currentSensitivityMode
    ) -> String {
        if score >= mode.goodThreshold { return "\u{1F929}" }  // star-struck
        if score >= mode.correctionThreshold { return "\u{1F642}" }  // slightly smiling
        if score >= mode.badThreshold { return "\u{1F610}" }  // neutral
        return "\u{2615}\u{FE0F}"  // hot beverage (break)
    }

    // MARK: - Helpers

    private static func relativeChange(baseline: CGFloat, current: CGFloat) -> CGFloat {
        guard baseline != 0 else { return 0 }
        return (current - baseline) / baseline
    }
}
