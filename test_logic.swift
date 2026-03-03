// Unit test for core logic without camera/Vision
// Tests: PostureAnalyzer, CalibrationManager, FeedbackEngine, score mapping

import Foundation

@main
struct TestRunner {
    static func main() {
        var totalPassed = 0
        var totalTests = 0

        // ===== Test 1: CVA to Score mapping =====
        print("=== Test 1: CVA to Score mapping ===")
        let testCases: [(cva: CGFloat, expectedRange: ClosedRange<Int>)] = [
            (15, 0...10),
            (20, 10...20),
            (35, 35...50),
            (50, 65...80),
            (60, 85...98),
            (65, 95...100),
        ]
        for tc in testCases {
            totalTests += 1
            let score = PostureAnalyzer.cvaToScore(tc.cva)
            let ok = tc.expectedRange.contains(score)
            print("  CVA \(tc.cva)° → score \(score) (expect \(tc.expectedRange)): \(ok ? "PASS" : "FAIL")")
            if ok { totalPassed += 1 }
        }

        // ===== Test 2: Score to Emoji =====
        print("\n=== Test 2: Score to Emoji ===")
        let emojiTests: [(score: Int, expected: String)] = [
            (90, "\u{1F929}"),
            (70, "\u{1F60A}"),
            (45, "\u{1F610}"),
            (25, "\u{1F615}"),
            (10, "\u{1F62C}"),
        ]
        for et in emojiTests {
            totalTests += 1
            let emoji = PostureAnalyzer.scoreToEmoji(et.score)
            let ok = emoji == et.expected
            print("  Score \(et.score) → \(emoji) (expect \(et.expected)): \(ok ? "PASS" : "FAIL")")
            if ok { totalPassed += 1 }
        }

        // ===== Test 3: Severity classification =====
        print("\n=== Test 3: Severity Classification ===")
        let sevTests: [(cva: CGFloat, expected: Severity)] = [
            (55, .good),
            (45, .mild),
            (30, .moderate),
            (20, .severe),
            (50, .good),
            (38, .mild),
            (25, .moderate),
            (24, .severe),
        ]
        for st in sevTests {
            totalTests += 1
            let severity = PostureAnalyzer.classifySeverity(st.cva)
            let ok = severity == st.expected
            print("  CVA \(st.cva)° → \(severity) (expect \(st.expected)): \(ok ? "PASS" : "FAIL")")
            if ok { totalPassed += 1 }
        }

        // ===== Test 4: CalibrationManager flow =====
        print("\n=== Test 4: Calibration Flow ===")
        let calManager = CalibrationManager()
        calManager.startCalibration()

        totalTests += 1
        let calStartOk = calManager.isCalibrating == true
        print("  isCalibrating: \(calManager.isCalibrating) (expect true): \(calStartOk ? "PASS" : "FAIL")")
        if calStartOk { totalPassed += 1 }

        // Feed 30 samples with good posture metrics
        let goodMetrics = PostureMetrics(
            earShoulderDistanceLeft: 150,
            earShoulderDistanceRight: 150,
            eyeShoulderDistanceLeft: 140,
            eyeShoulderDistanceRight: 140,
            headForwardRatio: 0.8,
            headTiltAngle: 0,
            neckEarAngle: 55,  // Good CVA
            shoulderEvenness: 2,
            earsVisible: true,
            landmarksDetected: true
        )

        var calResult: CalibrationResult?
        for i in 1...30 {
            calResult = calManager.addSample(goodMetrics)
            if i < 30 {
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

        // Test bad posture calibration
        print("\n  Testing bad posture calibration (CVA < 35°):")
        let calManager2 = CalibrationManager()
        calManager2.startCalibration()
        let badMetrics = PostureMetrics(
            earShoulderDistanceLeft: 150,
            earShoulderDistanceRight: 150,
            eyeShoulderDistanceLeft: 140,
            eyeShoulderDistanceRight: 140,
            headForwardRatio: 1.2,
            headTiltAngle: 0,
            neckEarAngle: 25,  // Bad CVA - too far forward
            shoulderEvenness: 2,
            earsVisible: true,
            landmarksDetected: true
        )
        var badResult: CalibrationResult?
        for _ in 1...30 {
            badResult = calManager2.addSample(badMetrics)
        }
        totalTests += 1
        let badInvalid = badResult?.isValid == false
        print("  isValid: \(badResult?.isValid ?? true) (expect false): \(badInvalid ? "PASS" : "FAIL")")
        if badInvalid { totalPassed += 1 }

        // ===== Test 5: PostureAnalyzer.evaluate =====
        print("\n=== Test 5: Posture Evaluation ===")
        let baseline = CalibrationData(
            earShoulderDistanceLeft: 150,
            earShoulderDistanceRight: 150,
            eyeShoulderDistanceLeft: 140,
            eyeShoulderDistanceRight: 140,
            headForwardRatio: 0.8,
            headTiltAngle: 0,
            neckEarAngle: 55,
            shoulderEvenness: 2,
            earsWereVisible: true
        )

        // Good posture
        let goodState = PostureAnalyzer.evaluate(
            metrics: goodMetrics,
            baseline: baseline,
            previousState: .initial,
            cameraPosition: .center
        )
        totalTests += 1
        let goodOk = goodState.severity == .good && !goodState.isTurtleNeck
        print("  Good posture: severity=\(goodState.severity) isTurtle=\(goodState.isTurtleNeck) (expect good, false): \(goodOk ? "PASS" : "FAIL")")
        if goodOk { totalPassed += 1 }

        // Bad posture (head forward)
        let forwardMetrics = PostureMetrics(
            earShoulderDistanceLeft: 100,
            earShoulderDistanceRight: 100,
            eyeShoulderDistanceLeft: 95,
            eyeShoulderDistanceRight: 95,
            headForwardRatio: 1.3,
            headTiltAngle: 0,
            neckEarAngle: 28,
            shoulderEvenness: 2,
            earsVisible: true,
            landmarksDetected: true
        )

        let badState = PostureAnalyzer.evaluate(
            metrics: forwardMetrics,
            baseline: baseline,
            previousState: .initial,
            cameraPosition: .center
        )
        totalTests += 1
        let badSevOk = badState.severity == .moderate
        print("  Bad posture: severity=\(badState.severity) deviation=\(String(format: "%.3f", badState.deviationScore)) (expect moderate): \(badSevOk ? "PASS" : "FAIL")")
        if badSevOk { totalPassed += 1 }

        // Sustained bad posture (simulate 6 seconds)
        let oldStart = Date().addingTimeInterval(-6)
        let sustainedPrev = PostureState(
            badPostureStart: oldStart,
            isTurtleNeck: false,
            deviationScore: 0.5,
            usingFallback: false,
            severity: .moderate,
            currentCVA: 28,
            baselineCVA: 55
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

        // ===== Test 6: FeedbackEngine =====
        print("\n=== Test 6: FeedbackEngine ===")
        let msg0 = FeedbackEngine.goodMessage(forDuration: 0)
        let msg60 = FeedbackEngine.goodMessage(forDuration: 60)
        let msg300 = FeedbackEngine.goodMessage(forDuration: 300)

        totalTests += 1
        let msg0ok = msg0.main == "Good posture!"
        print("  0s: \(msg0.main) (expect 'Good posture!'): \(msg0ok ? "PASS" : "FAIL")")
        if msg0ok { totalPassed += 1 }

        totalTests += 1
        let msg60ok = msg60.main == "Great job!"
        print("  60s: \(msg60.main) (expect 'Great job!'): \(msg60ok ? "PASS" : "FAIL")")
        if msg60ok { totalPassed += 1 }

        totalTests += 1
        let msg300ok = msg300.main == "Posture champion!"
        print("  300s: \(msg300.main) (expect 'Posture champion!'): \(msg300ok ? "PASS" : "FAIL")")
        if msg300ok { totalPassed += 1 }

        totalTests += 1
        let tip0 = FeedbackEngine.warningTip(index: 0)
        let tip0ok = tip0 == "Try pulling your chin back slightly"
        print("  Warning tip 0: \(tip0): \(tip0ok ? "PASS" : "FAIL")")
        if tip0ok { totalPassed += 1 }

        totalTests += 1
        let fmt90 = FeedbackEngine.formatTime(90)
        let fmt90ok = fmt90 == "1m 30s"
        print("  Format 90s: \(fmt90) (expect '1m 30s'): \(fmt90ok ? "PASS" : "FAIL")")
        if fmt90ok { totalPassed += 1 }

        totalTests += 1
        let fmt3600 = FeedbackEngine.formatTime(3600)
        let fmt3600ok = fmt3600 == "60m"
        print("  Format 3600s: \(fmt3600) (expect '60m'): \(fmt3600ok ? "PASS" : "FAIL")")
        if fmt3600ok { totalPassed += 1 }

        // ===== Test 7: CameraPosition =====
        print("\n=== Test 7: CameraPosition ===")

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

        totalTests += 1
        let rightPrimary = CameraPosition.right.primarySide == "left"
        print("  right.primarySide: \(CameraPosition.right.primarySide) (expect left): \(rightPrimary ? "PASS" : "FAIL")")
        if rightPrimary { totalPassed += 1 }

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
