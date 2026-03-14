// Unit test for core logic without camera/Vision
// Tests: PostureAnalyzer relative scoring, CalibrationManager, FeedbackEngine

import Foundation

@main
struct TestRunner {
    static func main() {
        var totalPassed = 0
        var totalTests = 0

        // ===== Test 1: Relative Score mapping =====
        print("=== Test 1: Relative Score (CVA deviation from baseline) ===")
        let relTests: [(current: CGFloat, baseline: CGFloat, expectedRange: ClosedRange<Int>)] = [
            (50, 50, 90...98),    // 0% deviation = perfect
            (42.5, 50, 68...78),  // 15% deviation
            (35, 50, 45...55),    // 30% deviation
            (25, 50, 15...25),    // 50% deviation
            (10, 50, 2...5),      // 80% deviation
            (50, 50, 90...98),    // same as baseline
        ]
        for tc in relTests {
            totalTests += 1
            let score = PostureAnalyzer.relativeScore(currentCVA: tc.current, baselineCVA: tc.baseline)
            let ok = tc.expectedRange.contains(score)
            print("  CVA \(tc.current)/\(tc.baseline) → score \(score) (expect \(tc.expectedRange)): \(ok ? "PASS" : "FAIL")")
            if ok { totalPassed += 1 }
        }

        // ===== Test 2: Score to Emoji =====
        print("\n=== Test 2: Score to Emoji ===")
        let emojiTests: [(score: Int, expected: String)] = [
            (90, "\u{1F929}"),    // star-struck (good)
            (60, "\u{1F642}"),    // slightly smiling (correction)
            (40, "\u{1F610}"),    // neutral (bad)
            (20, "\u{2615}\u{FE0F}"),  // hot beverage (away)
        ]
        for et in emojiTests {
            totalTests += 1
            let emoji = PostureAnalyzer.scoreToEmoji(et.score)
            let ok = emoji == et.expected
            print("  Score \(et.score) → \(emoji) (expect \(et.expected)): \(ok ? "PASS" : "FAIL")")
            if ok { totalPassed += 1 }
        }

        // ===== Test 3: Severity classification (score-based) =====
        print("\n=== Test 3: Severity Classification (score-based) ===")
        let sevTests: [(score: Int, expected: Severity)] = [
            (90, .good),
            (75, .good),
            (74, .correction),
            (55, .correction),
            (54, .bad),
            (35, .bad),
            (34, .away),
            (10, .away),
        ]
        for st in sevTests {
            totalTests += 1
            let severity = PostureAnalyzer.classifySeverity(score: st.score)
            let ok = severity == st.expected
            print("  Score \(st.score) → \(severity) (expect \(st.expected)): \(ok ? "PASS" : "FAIL")")
            if ok { totalPassed += 1 }
        }

        // ===== Test 4: CalibrationManager flow =====
        print("\n=== Test 4: Calibration Flow (median + variance gate) ===")
        let calManager = CalibrationManager()
        calManager.startCalibration()

        totalTests += 1
        let calStartOk = calManager.isCalibrating == true
        print("  isCalibrating: \(calManager.isCalibrating) (expect true): \(calStartOk ? "PASS" : "FAIL")")
        if calStartOk { totalPassed += 1 }

        // Feed 20 samples with good posture metrics
        let goodMetrics = PostureMetrics(
            earShoulderDistanceLeft: 150,
            earShoulderDistanceRight: 150,
            eyeShoulderDistanceLeft: 140,
            eyeShoulderDistanceRight: 140,
            headForwardRatio: 0.8,
            headTiltAngle: 0,
            neckEarAngle: 55,  // Good CVA
            headPitch: 5,
            faceSizeNormalized: 0.1,
            shoulderEvenness: 2,
            earsVisible: true,
            landmarksDetected: true,
            forwardDepth: 0.02,
            irisGazeOffset: 0.01
        )

        var calResult: CalibrationResult?
        for i in 1...20 {
            calResult = calManager.addSample(goodMetrics)
            if i < 20 {
                totalTests += 1
                let ok = calResult == nil
                if ok { totalPassed += 1 }
            }
        }

        totalTests += 1
        let gotResult = calResult != nil
        print("  Got calibration result: \(gotResult) (expect true): \(gotResult ? "PASS" : "FAIL")")
        if gotResult { totalPassed += 1 }

        totalTests += 1
        let isValid = calResult?.isValid ?? false
        print("  isValid: \(isValid) (expect true): \(isValid ? "PASS" : "FAIL")")
        if isValid { totalPassed += 1 }

        totalTests += 1
        let measuredCVA = calResult?.measuredCVA ?? 0
        let cvaOk = abs(measuredCVA - 55) < 1
        print("  measuredCVA: \(measuredCVA) (expect ~55): \(cvaOk ? "PASS" : "FAIL")")
        if cvaOk { totalPassed += 1 }

        totalTests += 1
        let calDone = calManager.isCalibrating == false
        print("  isCalibrating after: \(calManager.isCalibrating) (expect false): \(calDone ? "PASS" : "FAIL")")
        if calDone { totalPassed += 1 }

        // Verify schema version 2 and quality metadata
        totalTests += 1
        let schema2 = calResult?.data?.schemaVersion == 2
        print("  schemaVersion: \(calResult?.data?.schemaVersion ?? 0) (expect 2): \(schema2 ? "PASS" : "FAIL")")
        if schema2 { totalPassed += 1 }

        totalTests += 1
        let stdDevOk = (calResult?.data?.cvaStdDev ?? 999) < 1.0  // all identical samples → stdDev ≈ 0
        print("  cvaStdDev: \(calResult?.data?.cvaStdDev ?? -1) (expect ~0): \(stdDevOk ? "PASS" : "FAIL")")
        if stdDevOk { totalPassed += 1 }

        totalTests += 1
        let confOk = (calResult?.data?.landmarkConfidence ?? 0) >= 1.0  // all valid
        print("  landmarkConfidence: \(calResult?.data?.landmarkConfidence ?? -1) (expect 1.0): \(confOk ? "PASS" : "FAIL")")
        if confOk { totalPassed += 1 }

        // Test high-variance calibration (should fail)
        print("\n  Testing high-variance calibration:")
        let calManager2 = CalibrationManager()
        calManager2.startCalibration()
        var badResult: CalibrationResult?
        for i in 1...20 {
            // Alternate between CVA 20 and CVA 60 to create high variance
            let cva: CGFloat = i % 2 == 0 ? 20 : 60
            let varMetrics = PostureMetrics(
                earShoulderDistanceLeft: 150,
                earShoulderDistanceRight: 150,
                eyeShoulderDistanceLeft: 140,
                eyeShoulderDistanceRight: 140,
                headForwardRatio: 0.8,
                headTiltAngle: 0,
                neckEarAngle: cva,
                headPitch: 5,
                faceSizeNormalized: 0.1,
                shoulderEvenness: 2,
                earsVisible: true,
                landmarksDetected: true,
                forwardDepth: 0.02,
                irisGazeOffset: 0.01
            )
            badResult = calManager2.addSample(varMetrics)
        }
        totalTests += 1
        let highVarInvalid = badResult?.isValid == false
        print("  High variance isValid: \(badResult?.isValid ?? true) (expect false): \(highVarInvalid ? "PASS" : "FAIL")")
        if highVarInvalid { totalPassed += 1 }

        // ===== Test 5: PostureAnalyzer.evaluate =====
        print("\n=== Test 5: Posture Evaluation (relative scoring) ===")
        let baseline = CalibrationData(
            earShoulderDistanceLeft: 150,
            earShoulderDistanceRight: 150,
            eyeShoulderDistanceLeft: 140,
            eyeShoulderDistanceRight: 140,
            headForwardRatio: 0.8,
            headTiltAngle: 0,
            neckEarAngle: 55,
            shoulderEvenness: 2,
            earsWereVisible: true,
            schemaVersion: 2
        )

        // Good posture (same as baseline)
        let goodState = PostureAnalyzer.evaluate(
            metrics: goodMetrics,
            baseline: baseline,
            previousState: .initial,
            cameraPosition: .center
        )
        totalTests += 1
        let goodOk = goodState.severity == Severity.good && !goodState.isTurtleNeck
        print("  Good posture: severity=\(goodState.severity) score=\(goodState.score) (expect good, >=80): \(goodOk ? "PASS" : "FAIL")")
        if goodOk { totalPassed += 1 }

        totalTests += 1
        let goodScoreOk = goodState.score >= 80
        print("  Good posture score: \(goodState.score) (expect >=80): \(goodScoreOk ? "PASS" : "FAIL")")
        if goodScoreOk { totalPassed += 1 }

        // Bad posture (head forward, CVA dropped)
        let forwardMetrics = PostureMetrics(
            earShoulderDistanceLeft: 100,
            earShoulderDistanceRight: 100,
            eyeShoulderDistanceLeft: 95,
            eyeShoulderDistanceRight: 95,
            headForwardRatio: 1.3,
            headTiltAngle: 0,
            neckEarAngle: 28,  // ~49% deviation from baseline 55
            headPitch: 8,
            faceSizeNormalized: 0.12,
            shoulderEvenness: 2,
            earsVisible: true,
            landmarksDetected: true,
            forwardDepth: 0.05,
            irisGazeOffset: 0.02
        )

        let badState = PostureAnalyzer.evaluate(
            metrics: forwardMetrics,
            baseline: baseline,
            previousState: .initial,
            cameraPosition: .center
        )
        totalTests += 1
        let badSevOk = badState.severity == Severity.bad || badState.severity == Severity.away
        print("  Bad posture: severity=\(badState.severity) score=\(badState.score) (expect bad/away): \(badSevOk ? "PASS" : "FAIL")")
        if badSevOk { totalPassed += 1 }

        totalTests += 1
        let badScoreOk = badState.score < 40
        print("  Bad posture score: \(badState.score) (expect <40): \(badScoreOk ? "PASS" : "FAIL")")
        if badScoreOk { totalPassed += 1 }

        // Sustained bad posture (simulate 6 seconds)
        let oldStart = Date().addingTimeInterval(-6)
        let sustainedPrev = PostureState(
            badPostureStart: oldStart,
            isTurtleNeck: false,
            deviationScore: 0.5,
            usingFallback: false,
            severity: .bad,
            classification: .forwardHead,
            currentCVA: 28,
            baselineCVA: 55,
            score: 22
        )
        let turtleState = PostureAnalyzer.evaluate(
            metrics: forwardMetrics,
            baseline: baseline,
            previousState: sustainedPrev,
            cameraPosition: .center
        )
        totalTests += 1
        let turtleOk = turtleState.isTurtleNeck
        print("  Sustained 6s: isTurtle=\(turtleState.isTurtleNeck) (expect true): \(turtleOk ? "PASS" : "FAIL")")
        if turtleOk { totalPassed += 1 }

        // ===== Test 6: Composite relative score =====
        print("\n=== Test 6: Composite Relative Score ===")

        // Perfect posture (no deviation)
        totalTests += 1
        let perfectScore = PostureAnalyzer.compositeRelativeScore(
            currentCVA: 55, baselineCVA: 55,
            currentPitch: 5, baselinePitch: 5,
            currentFaceSize: 0.1, baselineFaceSize: 0.1,
            classification: .normal
        )
        let perfectOk = perfectScore >= 90
        print("  Perfect: \(perfectScore) (expect >=90): \(perfectOk ? "PASS" : "FAIL")")
        if perfectOk { totalPassed += 1 }

        // Mild forward head should separate more clearly from good.
        totalTests += 1
        let mildFhpScore = PostureAnalyzer.compositeRelativeScore(
            currentCVA: 46, baselineCVA: 55,
            currentPitch: 6, baselinePitch: 5,
            currentFaceSize: 0.086, baselineFaceSize: 0.1,
            currentForwardDepth: 0.05, baselineForwardDepth: 0.02,
            classification: .forwardHead
        )
        let mildFhpOk = mildFhpScore <= 60
        print("  Mild FHP: \(mildFhpScore) (expect <=60): \(mildFhpOk ? "PASS" : "FAIL")")
        if mildFhpOk { totalPassed += 1 }

        // Forward head (CVA dropped + face bigger)
        totalTests += 1
        let fhpScore = PostureAnalyzer.compositeRelativeScore(
            currentCVA: 38, baselineCVA: 55,
            currentPitch: 8, baselinePitch: 5,
            currentFaceSize: 0.12, baselineFaceSize: 0.1,
            currentForwardDepth: 0.08, baselineForwardDepth: 0.02,
            classification: .forwardHead
        )
        let fhpOk = fhpScore < 60
        print("  FHP: \(fhpScore) (expect <60): \(fhpOk ? "PASS" : "FAIL")")
        if fhpOk { totalPassed += 1 }

        // Looking down (pitch penalty partially recovered)
        totalTests += 1
        let downScore = PostureAnalyzer.compositeRelativeScore(
            currentCVA: 38, baselineCVA: 55,
            currentPitch: 20, baselinePitch: 5,
            currentFaceSize: 0.1, baselineFaceSize: 0.1,
            classification: .lookingDown
        )
        let downVsFhp = downScore > fhpScore  // looking down should score higher than same CVA with FHP
        print("  LookingDown: \(downScore) vs FHP: \(fhpScore) (expect down > fhp): \(downVsFhp ? "PASS" : "FAIL")")
        if downVsFhp { totalPassed += 1 }

        totalTests += 1
        let goodVsMildOk = perfectScore - mildFhpScore >= 30
        print("  Good vs Mild FHP gap: \(perfectScore - mildFhpScore) (expect >=30): \(goodVsMildOk ? "PASS" : "FAIL")")
        if goodVsMildOk { totalPassed += 1 }

        totalTests += 1
        let belowEyeMildFhpScore = PostureAnalyzer.compositeRelativeScore(
            currentCVA: 55, baselineCVA: 55,
            currentPitch: 1, baselinePitch: 6,
            currentFaceSize: 0.104, baselineFaceSize: 0.1,
            currentForwardDepth: 0.10, baselineForwardDepth: 0.02,
            classification: .forwardHead
        )
        let belowEyeMildFhpOk = belowEyeMildFhpScore <= 78
        print("  Below-eye mild FHP: \(belowEyeMildFhpScore) (expect <=78): \(belowEyeMildFhpOk ? "PASS" : "FAIL")")
        if belowEyeMildFhpOk { totalPassed += 1 }

        totalTests += 1
        let belowEyeDownScore = PostureAnalyzer.compositeRelativeScore(
            currentCVA: 60, baselineCVA: 62,
            currentPitch: 10, baselinePitch: 5,
            currentFaceSize: 0.099, baselineFaceSize: 0.1,
            currentForwardDepth: 0.025, baselineForwardDepth: 0.02,
            classification: .lookingDown
        )
        let belowEyeDownOk = belowEyeDownScore >= 88 && belowEyeDownScore > belowEyeMildFhpScore
        print("  Below-eye lookingDown: \(belowEyeDownScore) (expect >=88 and > below-eye mild FHP): \(belowEyeDownOk ? "PASS" : "FAIL")")
        if belowEyeDownOk { totalPassed += 1 }

        // ===== Test 7: Eye-level narrow helper (log-only) =====
        print("\n=== Test 7: Eye-Level Narrow Helper ===")

        totalTests += 1
        let eyeLevelGood = PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: 1.5,
            pitchDrop: 2.5,
            faceSizeChange: -0.01,
            depthIncrease: 0.01,
            yawDegrees: 2.0,
            irisGazeOffset: 0.08
        )
        let eyeLevelGoodOk =
            eyeLevelGood.classification == .inconclusive &&
            eyeLevelGood.confidence == 0
        print("  Good/neutral helper: class=\(eyeLevelGood.classification.rawValue) conf=\(eyeLevelGood.confidence) (expect inconclusive/0): \(eyeLevelGoodOk ? "PASS" : "FAIL")")
        if eyeLevelGoodOk { totalPassed += 1 }

        totalTests += 1
        let eyeLevelForward = PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: 9.0,
            pitchDrop: 2.0,
            faceSizeChange: -0.10,
            depthIncrease: 0.08,
            yawDegrees: 4.0,
            irisGazeOffset: 0.05
        )
        let eyeLevelForwardOk =
            eyeLevelForward.classification == .forwardHead &&
            eyeLevelForward.confidence >= 0.20 &&
            eyeLevelForward.forwardHeadEvidence > eyeLevelForward.lookingDownEvidence
        print("  ForwardHead narrow helper: class=\(eyeLevelForward.classification.rawValue) conf=\(eyeLevelForward.confidence) (expect forwardHead): \(eyeLevelForwardOk ? "PASS" : "FAIL")")
        if eyeLevelForwardOk { totalPassed += 1 }

        totalTests += 1
        let eyeLevelLookingDown = PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: 5.0,
            pitchDrop: 9.0,
            faceSizeChange: -0.01,
            depthIncrease: 0.00,
            yawDegrees: 3.0,
            irisGazeOffset: 0.34
        )
        let eyeLevelLookingDownOk =
            eyeLevelLookingDown.classification == .lookingDown &&
            eyeLevelLookingDown.confidence >= 0.20 &&
            eyeLevelLookingDown.lookingDownEvidence > eyeLevelLookingDown.forwardHeadEvidence
        print("  LookingDown narrow helper: class=\(eyeLevelLookingDown.classification.rawValue) conf=\(eyeLevelLookingDown.confidence) (expect lookingDown): \(eyeLevelLookingDownOk ? "PASS" : "FAIL")")
        if eyeLevelLookingDownOk { totalPassed += 1 }

        totalTests += 1
        let eyeLevelMixed = PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: 6.0,
            pitchDrop: 7.0,
            faceSizeChange: -0.03,
            depthIncrease: 0.02,
            yawDegrees: 5.0,
            irisGazeOffset: 0.18
        )
        let eyeLevelMixedOk =
            eyeLevelMixed.classification == .inconclusive &&
            eyeLevelMixed.confidence < 0.30
        print("  Mixed/inconclusive helper: class=\(eyeLevelMixed.classification.rawValue) conf=\(eyeLevelMixed.confidence) (expect inconclusive): \(eyeLevelMixedOk ? "PASS" : "FAIL")")
        if eyeLevelMixedOk { totalPassed += 1 }

        totalTests += 1
        let eyeLevelYawFallback = PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: 9.0,
            pitchDrop: 2.0,
            faceSizeChange: -0.10,
            depthIncrease: 0.08,
            yawDegrees: 25.0,
            irisGazeOffset: 0.05
        )
        let eyeLevelYawFallbackOk =
            eyeLevelYawFallback.classification == .inconclusive &&
            eyeLevelYawFallback.confidence == 0
        print("  High-yaw helper fallback: class=\(eyeLevelYawFallback.classification.rawValue) conf=\(eyeLevelYawFallback.confidence) (expect inconclusive/0): \(eyeLevelYawFallbackOk ? "PASS" : "FAIL")")
        if eyeLevelYawFallbackOk { totalPassed += 1 }

        // ===== Test 8: FeedbackEngine =====
        print("\n=== Test 8: FeedbackEngine ===")
        let msg0 = FeedbackEngine.goodMessage(forDuration: 0)
        let msg60 = FeedbackEngine.goodMessage(forDuration: 60)
        let msg300 = FeedbackEngine.goodMessage(forDuration: 300)

        totalTests += 1
        let msg0ok = msg0.main == "Good posture"
        print("  0s: \(msg0.main) (expect 'Good posture'): \(msg0ok ? "PASS" : "FAIL")")
        if msg0ok { totalPassed += 1 }

        totalTests += 1
        let msg60ok = msg60.main == "1 min solid"
        print("  60s: \(msg60.main) (expect '1 min solid'): \(msg60ok ? "PASS" : "FAIL")")
        if msg60ok { totalPassed += 1 }

        totalTests += 1
        let msg300ok = msg300.main == "5 min in"
        print("  300s: \(msg300.main) (expect '5 min in'): \(msg300ok ? "PASS" : "FAIL")")
        if msg300ok { totalPassed += 1 }

        totalTests += 1
        let tip0 = FeedbackEngine.warningTip(index: 0)
        let tip0ok = tip0 == "Tuck your chin back gently."
        print("  Warning tip 0: \(tip0): \(tip0ok ? "PASS" : "FAIL")")
        if tip0ok { totalPassed += 1 }

        totalTests += 1
        let fmt90 = FeedbackEngine.formatTime(90)
        let fmt90ok = fmt90 == "1m 30s"
        print("  Format 90s: \(fmt90) (expect '1m 30s'): \(fmt90ok ? "PASS" : "FAIL")")
        if fmt90ok { totalPassed += 1 }

        // ===== Test 9: CameraPosition =====
        print("\n=== Test 9: CameraPosition ===")

        totalTests += 1
        let centerOk = CameraPosition.center.isSideView == false
        print("  center.isSideView: \(CameraPosition.center.isSideView) (expect false): \(centerOk ? "PASS" : "FAIL")")
        if centerOk { totalPassed += 1 }

        totalTests += 1
        let leftSide = CameraPosition.left.isSideView == true
        print("  left.isSideView: \(CameraPosition.left.isSideView) (expect true): \(leftSide ? "PASS" : "FAIL")")
        if leftSide { totalPassed += 1 }

        totalTests += 1
        let leftPrimary = CameraPosition.left.primarySide == "right"
        print("  left.primarySide: \(CameraPosition.left.primarySide) (expect right): \(leftPrimary ? "PASS" : "FAIL")")
        if leftPrimary { totalPassed += 1 }

        // ===== Summary =====
        print("\n=============================")
        print("TOTAL: \(totalPassed)/\(totalTests) passed")
        let allPassed = totalPassed == totalTests
        print(allPassed ? "ALL TESTS PASSED ✓" : "SOME TESTS FAILED ✗")
        print("=============================")

        if !allPassed {
            exit(1)
        }
    }
}
