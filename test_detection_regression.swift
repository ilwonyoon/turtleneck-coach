import Foundation

@main
struct DetectionRegressionTestRunner {
    static func main() async {
        await MainActor.run {
            var totalPassed = 0
            var totalTests = 0

            func check(_ condition: @autoclosure () -> Bool, _ label: String) {
                totalTests += 1
                let ok = condition()
                print("  \(label): \(ok ? "PASS" : "FAIL")")
                if ok { totalPassed += 1 }
            }

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
                headPitch: 5,
                baselineFaceSize: 0.1,
                forwardDepth: 0.02,
                irisGazeOffset: 0.01,
                cvaStdDev: 0.3,
                landmarkConfidence: 1.0,
                baselineYaw: 0,
                schemaVersion: 2
            )

            let goodState = PostureState(
                badPostureStart: nil,
                isTurtleNeck: false,
                deviationScore: 0,
                usingFallback: false,
                severity: .good,
                classification: .normal,
                currentCVA: 55,
                baselineCVA: 55,
                score: 95
            )

            print("=== Test 1: Detection loss updates live status immediately ===")
            let statusEngine = PostureEngine()
            let statusStart = Date(timeIntervalSinceNow: -120)
            statusEngine.debugPrimeSessionForTesting(
                startDate: statusStart,
                calibrationData: baseline,
                postureState: goodState,
                bodyDetected: true,
                powerState: .active
            )
            check(statusEngine.dashboardLiveStatusText == "Monitoring", "dashboard shows monitoring before loss")
            check(statusEngine.menuBarStatusText == "Great", "menu bar shows held posture before loss")

            let lossTime = statusStart.addingTimeInterval(30)
            statusEngine.debugHandleDetectionLossForTesting(at: lossTime)
            check(statusEngine.dashboardLiveStatusText == "No body detected", "dashboard shows no body detected after loss")
            check(statusEngine.menuBarStatusText == "No Body", "menu bar shows no body after loss")
            check(statusEngine.goodPostureStart == nil, "good posture streak clears after loss")

            statusEngine.powerState = .inactive
            check(statusEngine.dashboardLiveStatusText == "Paused", "dashboard shows paused in inactive mode")
            check(statusEngine.menuBarStatusText == "Paused", "menu bar shows paused in inactive mode")

            print("\n=== Test 2: No-detection gap does not inflate monitored time ===")
            let sessionEngine = PostureEngine()
            let sessionStart = Date(timeIntervalSinceNow: -300)
            sessionEngine.debugPrimeSessionForTesting(
                startDate: sessionStart,
                calibrationData: baseline,
                postureState: goodState,
                bodyDetected: true,
                powerState: .active
            )

            let monitoredUntil = sessionStart.addingTimeInterval(30)
            sessionEngine.debugAdvanceSessionClockForTesting(to: monitoredUntil)
            sessionEngine.debugHandleDetectionLossForTesting(at: monitoredUntil)

            let snapshot = sessionEngine.currentSessionSnapshot()
            check(snapshot != nil, "snapshot exists after monitored interval")
            if let snapshot {
                check(abs(snapshot.duration - 30) < 0.25, "duration remains 30s after no-detection gap")
                check(abs(snapshot.goodPosturePercent - 100) < 0.01, "good posture percent stays at 100%")
                check(snapshot.badPostureSeconds == 0, "bad posture seconds stay at zero")
            } else {
                totalTests += 3
            }

            print("\nResult: \(totalPassed)/\(totalTests) passed")
            exit(totalPassed == totalTests ? 0 : 1)
        }
    }
}
