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

    // CVA boundaries used for menu bar transition hysteresis.
    // Derived from the score mapping curve (CVA 20-65° -> score 5-98).
    static var cvaGood: CGFloat {
        cvaGood(for: currentSensitivityMode)
    }

    static var cvaCorrection: CGFloat {
        cvaCorrection(for: currentSensitivityMode)
    }

    static var cvaBad: CGFloat {
        cvaBad(for: currentSensitivityMode)
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
                baselineCVA: baseline.neckEarAngle
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

        // Debug: log classifier inputs every ~3s
        let pitchDelta = metrics.headPitch - baseline.headPitch
        let fsc = baseline.baselineFaceSize > 0 ? (metrics.faceSizeNormalized - baseline.baselineFaceSize) / baseline.baselineFaceSize : 0
        let debugLine = String(format: "[CLASSIFY] pitch=%.2f base=%.2f Δ=%.3f faceSize=%.4f base=%.4f Δ=%.1f%% cvaDrop=%.1f yaw=%.1f fwdZ=%.4f baseZ=%.4f iris=%.3f baseIris=%.3f → %@",
            metrics.headPitch, baseline.headPitch, pitchDelta,
            metrics.faceSizeNormalized, baseline.baselineFaceSize, fsc * 100,
            cvaDrop, abs(yawDegrees),
            metrics.forwardDepth, baseline.forwardDepth,
            metrics.irisGazeOffset, baseline.irisGazeOffset,
            classification.rawValue)
        if let data = (debugLine + "\n").data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        }

        let adjustedCVA: CGFloat
        if classification == .lookingDown {
            let drop = baseline.neckEarAngle - metrics.neckEarAngle
            adjustedCVA = metrics.neckEarAngle + drop * 0.5  // recover 50% of CVA drop
        } else {
            adjustedCVA = metrics.neckEarAngle
        }

        // Debug: log adjusted CVA and score
        let t = FHPTuning.shared
        let adjDebug = String(format: "[ADJUST] rawCVA=%.1f adjustedCVA=%.1f baseline=%.1f class=%@ score=%d [tuning: shrink=%.1f%% scale=%.0f pitch=%.1f°]",
            metrics.neckEarAngle, adjustedCVA, baseline.neckEarAngle,
            classification.rawValue, Int(Self.cvaToScore(adjustedCVA)),
            t.faceShrinkThreshold * 100, t.depthPenaltyScale, t.pitchGateDegrees)
        if let adjData = (adjDebug + "\n").data(using: .utf8) {
            let adjUrl = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
            if let fh = try? FileHandle(forWritingTo: adjUrl) {
                fh.seekToEndOfFile()
                fh.write(adjData)
                fh.closeFile()
            }
        }

        let severity = classifySeverity(adjustedCVA, mode: sensitivityMode)
        let useFallback = !metrics.earsVisible

        // When using face fallback, shoulder positions are estimated from face bbox
        // so distance-based deviation doesn't work. Use CVA drop as primary signal.
        let isCurrentlyBad: Bool
        let score: CGFloat

        if useFallback {
            // Face fallback mode: use CVA difference from baseline as the deviation signal
            let effectiveCVADrop = baseline.neckEarAngle - adjustedCVA
            // Normalize: 10° drop = moderate concern, 20° drop = severe
            score = max(0, effectiveCVADrop / baseline.neckEarAngle)
            // Bad if CVA dropped below "good" threshold or dropped significantly from baseline
            isCurrentlyBad = severity != .good || effectiveCVADrop > 8.0
        } else {
            // Body pose mode: use original distance-based deviation
            let forwardDeviation = relativeChange(
                baseline: baseline.headForwardRatio,
                current: metrics.headForwardRatio
            )

            if cameraPosition.isSideView {
                let vertScore = evaluateSideView(
                    metrics: metrics,
                    baseline: baseline,
                    cameraPosition: cameraPosition,
                    useFallback: useFallback
                )
                score = vertScore + max(0, forwardDeviation) * 0.3
            } else {
                let vertScore = evaluateCenterView(
                    metrics: metrics,
                    baseline: baseline,
                    useFallback: useFallback
                )
                score = vertScore + max(0, forwardDeviation)
            }

            let threshold = (Self.forwardRatioThreshold + Self.earShoulderThreshold) * 0.5
            isCurrentlyBad = score > threshold
        }

        let now = Date()

        if isCurrentlyBad {
            let start = previousState.badPostureStart ?? now
            let duration = now.timeIntervalSince(start)
            let isTurtle = duration >= Self.sustainedDurationSec
            return PostureState(
                badPostureStart: start,
                isTurtleNeck: isTurtle,
                deviationScore: score,
                usingFallback: useFallback,
                severity: severity,
                classification: classification,
                currentCVA: adjustedCVA,
                baselineCVA: baseline.neckEarAngle
            )
        }

        return PostureState(
            badPostureStart: nil,
            isTurtleNeck: false,
            deviationScore: score,
            usingFallback: useFallback,
            severity: severity,
            classification: classification,
            currentCVA: adjustedCVA,
            baselineCVA: baseline.neckEarAngle
        )
    }

    // MARK: - Severity Classification

    static func classifySeverity(
        _ cva: CGFloat,
        mode: SensitivityMode = currentSensitivityMode
    ) -> Severity {
        let score = cvaToScore(cva)
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

    /// Convert CVA angle to a 0-100 posture score.
    /// Narrower input range for MediaPipe: CVA 20-65° → score 5-98.
    /// More sensitive to posture changes with accurate landmarks.
    static func cvaToScore(_ cva: CGFloat) -> Int {
        if cva <= 20 { return 5 }
        if cva >= 65 { return 98 }
        return Int(round(5 + (cva - 20) * (93.0 / 45.0)))
    }

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

    static func cvaGood(for mode: SensitivityMode) -> CGFloat {
        cvaForScoreThreshold(mode.goodThreshold)
    }

    static func cvaCorrection(for mode: SensitivityMode) -> CGFloat {
        cvaForScoreThreshold(mode.correctionThreshold)
    }

    static func cvaBad(for mode: SensitivityMode) -> CGFloat {
        cvaForScoreThreshold(mode.badThreshold)
    }

    // MARK: - Helpers

    private static func cvaForScoreThreshold(_ score: Int) -> CGFloat {
        20 + (CGFloat(score) - 5) * (45.0 / 93.0)
    }

    private static func relativeChange(baseline: CGFloat, current: CGFloat) -> CGFloat {
        guard baseline != 0 else { return 0 }
        return (current - baseline) / baseline
    }
}
