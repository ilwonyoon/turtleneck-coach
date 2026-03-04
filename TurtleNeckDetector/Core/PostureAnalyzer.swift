import Foundation

/// Posture evaluation engine.
/// Port of Python detector.py - evaluates posture against calibration baseline.
struct PostureAnalyzer {

    // Deviation thresholds from baseline (from detector.py)
    static let forwardRatioThreshold: CGFloat = 0.15
    static let earShoulderThreshold: CGFloat = 0.20
    static let eyeShoulderThreshold: CGFloat = 0.18
    static let sideViewEarThreshold: CGFloat = 0.15
    static let sustainedDurationSec: TimeInterval = 5.0

    // Score severity thresholds:
    // 80+ good, 60-79 correction, 40-59 bad, <40 away.
    static let scoreGoodThreshold = 80
    static let scoreCorrectionThreshold = 60
    static let scoreBadThreshold = 40

    // CVA boundaries used for menu bar transition hysteresis.
    // Derived from the score mapping curve (CVA 20-65° -> score 5-98).
    static let cvaGood: CGFloat = cvaForScoreThreshold(scoreGoodThreshold)
    static let cvaCorrection: CGFloat = cvaForScoreThreshold(scoreCorrectionThreshold)
    static let cvaBad: CGFloat = cvaForScoreThreshold(scoreBadThreshold)

    /// Evaluate current posture metrics against calibration baseline.
    /// Returns a new PostureState (immutable pattern - creates new state each call).
    static func evaluate(
        metrics: PostureMetrics,
        baseline: CalibrationData,
        previousState: PostureState,
        cameraPosition: CameraPosition
    ) -> PostureState {
        guard metrics.landmarksDetected else {
            return PostureState(
                badPostureStart: previousState.badPostureStart,
                isTurtleNeck: false,
                deviationScore: 0,
                usingFallback: previousState.usingFallback,
                severity: .good,
                currentCVA: 0,
                baselineCVA: baseline.neckEarAngle
            )
        }

        let severity = classifySeverity(metrics.neckEarAngle)
        let useFallback = !metrics.earsVisible

        // When using face fallback, shoulder positions are estimated from face bbox
        // so distance-based deviation doesn't work. Use CVA drop as primary signal.
        let isCurrentlyBad: Bool
        let score: CGFloat

        if useFallback {
            // Face fallback mode: use CVA difference from baseline as the deviation signal
            let cvaDrop = baseline.neckEarAngle - metrics.neckEarAngle
            // Normalize: 10° drop = moderate concern, 20° drop = severe
            score = max(0, cvaDrop / baseline.neckEarAngle)
            // Bad if CVA dropped below "good" threshold or dropped significantly from baseline
            isCurrentlyBad = severity != .good || cvaDrop > 8.0
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
                currentCVA: metrics.neckEarAngle,
                baselineCVA: baseline.neckEarAngle
            )
        }

        return PostureState(
            badPostureStart: nil,
            isTurtleNeck: false,
            deviationScore: score,
            usingFallback: useFallback,
            severity: severity,
            currentCVA: metrics.neckEarAngle,
            baselineCVA: baseline.neckEarAngle
        )
    }

    // MARK: - Severity Classification

    static func classifySeverity(_ cva: CGFloat) -> Severity {
        let score = cvaToScore(cva)
        if score >= scoreGoodThreshold { return .good }
        if score >= scoreCorrectionThreshold { return .correction }
        if score >= scoreBadThreshold { return .bad }
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
    static func scoreToEmoji(_ score: Int) -> String {
        if score >= scoreGoodThreshold { return "\u{1F929}" }  // star-struck
        if score >= scoreCorrectionThreshold { return "\u{1F642}" }  // slightly smiling
        if score >= scoreBadThreshold { return "\u{1F610}" }  // neutral
        return "\u{2615}\u{FE0F}"  // hot beverage (break)
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
