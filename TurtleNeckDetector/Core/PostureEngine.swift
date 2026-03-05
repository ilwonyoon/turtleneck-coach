import SwiftUI
import Combine
import os

/// Main orchestrator: continuous camera -> periodic analysis -> UI + notifications.
@MainActor
final class PostureEngine: ObservableObject {

    // MARK: - Published State

    @Published var isMonitoring = false
    @Published var postureState = PostureState.initial
    @Published var calibrationData: CalibrationData?
    @Published var isCalibrating = false
    @Published var calibrationProgress: CGFloat = 0
    @Published var calibrationMessage = ""
    @Published var calibrationSuccess: Bool?
    @Published var cameraPosition: CameraPosition = .center {
        didSet {
            UserDefaults.standard.set(cameraPosition.rawValue, forKey: "cameraPosition")
        }
    }
    @Published var goodPostureStart: Date?
    @Published var lastError: String?
    @Published var currentFrame: CGImage?
    @Published var currentJoints: DetectedJoints?
    @Published var bodyDetected = false
    @AppStorage(SensitivityMode.storageKey)
    private var sensitivityModeRawValue = SensitivityMode.defaultMode.rawValue

    // Score history for 1-minute average
    private var scoreHistory: [(date: Date, score: Int)] = []

    // MARK: - Computed

    var postureScore: Int {
        PostureAnalyzer.cvaToScore(postureState.currentCVA)
    }

    private var sensitivityMode: SensitivityMode {
        let rawValue = UserDefaults.standard.string(forKey: SensitivityMode.storageKey) ?? sensitivityModeRawValue
        return SensitivityMode(rawValue: rawValue) ?? .balanced
    }

    var postureEmoji: String {
        PostureAnalyzer.scoreToEmoji(postureScore, mode: sensitivityMode)
    }

    /// Live score color mapped directly from the current posture score.
    /// Unlike `menuBarSeverityColor`, this should not be delayed by hold timers.
    var postureScoreColor: Color {
        let score = postureScore
        let mode = sensitivityMode
        if score >= mode.goodThreshold { return DS.Severity.good }
        if score >= mode.correctionThreshold { return DS.Severity.mild }
        if score >= mode.badThreshold { return DS.Severity.moderate }
        return DS.Severity.severe
    }

    /// 1-minute rolling average score for menu bar display.
    var averageScore: Int? {
        let cutoff = Date().addingTimeInterval(-60)
        let recent = scoreHistory.filter { $0.date > cutoff }
        guard !recent.isEmpty else { return nil }
        let sum = recent.reduce(0) { $0 + $1.score }
        return sum / recent.count
    }

    var goodPostureDuration: TimeInterval {
        guard let start = goodPostureStart else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Camera (public for session access if needed)

    let camera = CameraManager()
    let dataStore = PostureDataStore()

    // MARK: - Private

    private let poseDetector = VisionPoseDetector()
    private let mediaPipeClient = MediaPipeClient()
    private let calibrationManager = CalibrationManager()
    private let notificationService = NotificationService()
    private var analysisTimer: Timer?
    private var useMediaPipe = true  // prefer MediaPipe, fallback to Vision
    private var mediaPipeConnectAttempted = false
    private var lastMediaPipeHeadPitch: CGFloat = 0
    /// Current head yaw (horizontal rotation) — published for UI feedback
    @Published var currentHeadYaw: CGFloat = 0
    /// Current head pitch (forward tilt, 0=straight, positive=forward) — published for UI
    @Published var currentHeadPitch: CGFloat = 0

    // Menu bar held severity — only changes after sustained threshold
    @Published private(set) var menuBarSeverity: Severity = .good
    @Published private(set) var menuBarIsIdle = true
    private var pendingSeverity: Severity?
    private var pendingSeverityStart: Date?
    private var pendingTransitionStepCount = 0
    private var lastSuccessfulDetectionAt: Date?
    private let noDetectionIdleTimeout: TimeInterval = 10.0
    private let worsenInitialHold: TimeInterval = 1.0
    private let worsenFollowUpHold: TimeInterval = 0.5
    private let improveInitialHold: TimeInterval = 2.0
    private let improveFollowUpHold: TimeInterval = 1.0
    private let cvaBoundaryBuffer: CGFloat = 2.0
    private let cvaTransitionCrossover: CGFloat = 3.0

    // MARK: - Debug Capture
    @Published var debugCaptureLabel: String?
    private var debugCaptureStart: Date?
    private let debugCaptureDuration: TimeInterval = 5.0
    private var debugSnapshotTimer: Timer?
    private var debugSnapshotCount = 0

    func startDebugCapture(label: String) {
        debugCaptureLabel = label
        debugCaptureStart = Date()
        debugSnapshotCount = 0
        let header = "\n===== DEBUG CAPTURE: \(label) START =====\n"
        appendToDebugLog(header)
        // Take snapshot immediately, then every 1 second
        saveDebugSnapshot(label: label)
        debugSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveDebugSnapshot(label: label)
            }
        }
        // Auto-stop after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + debugCaptureDuration) { [weak self] in
            self?.stopDebugCapture()
        }
    }

    private func stopDebugCapture() {
        guard let label = debugCaptureLabel else { return }
        debugSnapshotTimer?.invalidate()
        debugSnapshotTimer = nil
        let footer = "===== DEBUG CAPTURE: \(label) END (\(debugSnapshotCount) snapshots saved) =====\n\n"
        appendToDebugLog(footer)
        debugCaptureLabel = nil
        debugCaptureStart = nil
    }

    private func saveDebugSnapshot(label: String) {
        guard let frame = currentFrame else { return }
        let idx = debugSnapshotCount
        debugSnapshotCount += 1
        let path = "/tmp/turtle_debug_snapshots/\(label)_\(idx).png"
        let rep = NSBitmapImageRep(cgImage: frame)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    private func appendToDebugLog(_ text: String) {
        if let data = text.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        }
    }

    // MARK: - Notification Suppression State
    private var sustainedBadStart: Date? = nil
    private let sustainedBadThreshold: TimeInterval = 25.0

    private var previousSmoothedCVA: CGFloat? = nil
    private var motionSuppressed = false
    private var lowDeltaFrameCount = 0
    private let motionDeltaThreshold: CGFloat = 5.0
    private let motionClearFrames = 3

    private var previousFaceSize: CGFloat? = nil
    private var scaleChangeHoldUntil: Date? = nil
    private let scaleChangeThreshold: CGFloat = 0.15
    private let scaleChangeHoldDuration: TimeInterval = 5.0

    private var recentNosePositions: [(date: Date, position: CGPoint)] = []
    private var jitterHoldUntil: Date? = nil
    private let jitterWindowSeconds: TimeInterval = 3.0
    private let jitterVarianceThreshold: CGFloat = 0.0008
    private let jitterHoldDuration: TimeInterval = 3.0

    var menuBarStatusText: String {
        guard !menuBarIsIdle else { return "—" }
        switch menuBarSeverity {
        case .good: return "Great"
        case .correction: return "Adjust"
        case .bad: return "Reset"
        case .away: return "Break"
        }
    }

    var menuBarIconColor: Color {
        guard !menuBarIsIdle else { return .secondary }
        return menuBarSeverityColor
    }

    var menuBarSeverityColor: Color {
        switch menuBarSeverity {
        case .good: return DS.Severity.good
        case .correction: return DS.Severity.mild
        case .bad: return DS.Severity.moderate
        case .away: return DS.Severity.severe
        }
    }

    // EMA smoothing for CVA — adaptive alpha based on jump size (computed per-frame)
    private var smoothedCVA: CGFloat? = nil

    // Thread-safe frame storage
    private let frameLock = NSLock()
    private var _pendingFrame: CGImage?
    // Throttle UI updates to ~15fps to avoid overwhelming SwiftUI
    private var lastUIUpdate: Date = .distantPast
    private let uiUpdateInterval: TimeInterval = 1.0 / 15.0

    // Session tracking + persistence
    private let periodicSessionSaveInterval: TimeInterval = 300
    private var sessionSaveTimer: Timer?
    private var activeSessionID: UUID?
    private var sessionStartDate: Date?
    private var sessionLastTick: Date?
    private var sessionTotalSeconds: TimeInterval = 0
    private var sessionGoodPostureSeconds: TimeInterval = 0
    private var sessionScoreSum: Double = 0
    private var sessionScoreSampleCount = 0
    private var sessionCVASum: Double = 0
    private var sessionCVASampleCount = 0
    private var sessionSlouchEventCount = 0

    // MARK: - Init

    init() {
        // Log engine creation
        let initLine = "\(Date()): [ENGINE] PostureEngine init\n"
        let initUrl = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
        if let fh = try? FileHandle(forWritingTo: initUrl) {
            fh.seekToEndOfFile()
            fh.write(initLine.data(using: .utf8)!)
            fh.closeFile()
        } else {
            try? initLine.data(using: .utf8)?.write(to: initUrl)
        }

        // No saved calibration loaded — always recalibrate on app start
        if let saved = UserDefaults.standard.string(forKey: "cameraPosition"),
           let pos = CameraPosition(rawValue: saved) {
            cameraPosition = pos
        }
        // Notification permission is requested after camera starts in OnboardingView.

        // Frame callback runs on camera's background queue
        // CameraManager already rotates portrait frames to landscape
        camera.onFrame = { [weak self] image in
            guard let self else { return }
            // Store for analysis
            self.frameLock.lock()
            self._pendingFrame = image
            self.frameLock.unlock()

            // Throttled UI update on main thread for live preview
            let now = Date()
            if now.timeIntervalSince(self.lastUIUpdate) >= self.uiUpdateInterval {
                self.lastUIUpdate = now
                DispatchQueue.main.async { [weak self] in
                    self?.currentFrame = image
                }
            }
        }
    }

    private func engineLog(_ msg: String) {
        let line = "\(Date()): [ENGINE] \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        }
    }

    private func grabPendingFrame() -> CGImage? {
        frameLock.lock()
        let frame = _pendingFrame
        frameLock.unlock()
        return frame
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastError = nil
        resetMenuBarForIdle()
        startSessionTracking()
        engineLog("startMonitoring called")

        Task {
            do {
                try await camera.start()
                // Small delay for camera warmup
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Try connecting to MediaPipe server
                if useMediaPipe && !mediaPipeConnectAttempted {
                    mediaPipeConnectAttempted = true
                    let connected = mediaPipeClient.connect()
                    if connected {
                        engineLog("MediaPipe server connected — using enhanced detection")
                    } else {
                        engineLog("MediaPipe server unavailable — falling back to Vision framework")
                    }
                }

                scheduleAnalysis()

                // Auto-calibrate on every start so baseline matches current session
                startCalibration()
            } catch CameraManager.CameraError.notAuthorized {
                lastError = "Camera access denied. Enable in System Settings > Privacy."
                isMonitoring = false
                resetSessionTracking()
            } catch {
                lastError = "Camera error: \(error.localizedDescription)"
                isMonitoring = false
                resetSessionTracking()
            }
        }
    }

    func stopMonitoring() {
        persistSessionSnapshot(endDate: Date())
        resetSessionTracking()
        isMonitoring = false
        analysisTimer?.invalidate()
        analysisTimer = nil
        camera.stop()
        mediaPipeClient.disconnect()
        mediaPipeConnectAttempted = false
        currentFrame = nil
        currentJoints = nil
        bodyDetected = false
        smoothedCVA = nil
        resetSuppressionState()
        resetMenuBarForIdle()
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func currentSessionSnapshot() -> SessionRecord? {
        buildSessionRecord(endDate: Date())
    }

    private func scheduleAnalysis() {
        analysisTimer?.invalidate()
        guard isMonitoring else { return }

        let interval = isCalibrating ? 0.2 : 0.33
        analysisTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.analyzeLatestFrame()
            }
        }
        // Run once immediately
        analyzeLatestFrame()
    }

    // MARK: - Analyze

    private func analyzeLatestFrame() {
        let now = Date()
        updateSessionTrackingClock(now: now)

        guard let image = grabPendingFrame() else {
            if Int.random(in: 0..<30) == 0 { engineLog("no pending frame") }
            updateMenuBarForNoDetection(at: now)
            return
        }
        if Int.random(in: 0..<10) == 0 { engineLog("analyzing frame \(image.width)x\(image.height)") }

        // Try MediaPipe first, then fall back to Vision framework
        let detectionResult: DetectionResult?
        let usingMediaPipe: Bool

        if useMediaPipe && mediaPipeClient.isConnected,
           let mpResult = mediaPipeClient.sendFrame(image),
           mpResult.confidence > 0.1 {
            // MediaPipe path — convert result to DetectionResult
            let joints = mediaPipeClient.resultToJoints(mpResult)
            let metrics = mediaPipeClient.resultToMetrics(mpResult, imageWidth: image.width, imageHeight: image.height)
            detectionResult = DetectionResult(metrics: metrics, joints: joints)
            lastMediaPipeHeadPitch = CGFloat(mpResult.headPitch)
            currentHeadPitch = CGFloat(mpResult.headPitch)
            currentHeadYaw = CGFloat(mpResult.headYaw)
            usingMediaPipe = true
        } else {
            // Vision framework fallback
            detectionResult = try? poseDetector.detect(in: image)
            usingMediaPipe = false

            // Try reconnecting MediaPipe periodically
            if useMediaPipe && !mediaPipeClient.isConnected && Int.random(in: 0..<90) == 0 {
                let connected = mediaPipeClient.connect()
                if connected {
                    engineLog("MediaPipe reconnected")
                }
            }
        }

        guard let result = detectionResult else {
            bodyDetected = false
            currentJoints = nil
            updateMenuBarForNoDetection(at: now)
            return
        }

        bodyDetected = true
        currentJoints = result.joints
        lastSuccessfulDetectionAt = now
        menuBarIsIdle = false
        if let mesh = result.joints.faceMesh {
            engineLog("faceMesh present: \(mesh.landmarks.count) landmarks, \(mesh.depthValues.count) depths")
        } else {
            engineLog("faceMesh=nil")
        }
        let rawCVA = result.metrics.neckEarAngle

        // Adaptive EMA smoothing — reduce alpha on large jumps to prevent oscillation
        let cvaDelta = abs(rawCVA - (smoothedCVA ?? rawCVA))
        let currentAlpha: CGFloat
        if cvaDelta > 10 {
            currentAlpha = 0.3  // large jump → smooth more aggressively
        } else {
            currentAlpha = usingMediaPipe ? 0.6 : 0.5
        }
        let smoothed: CGFloat
        if let prev = smoothedCVA {
            smoothed = currentAlpha * rawCVA + (1 - currentAlpha) * prev
        } else {
            smoothed = rawCVA
        }
        smoothedCVA = smoothed

        // Rebuild metrics with smoothed CVA
        let metrics = PostureMetrics(
            earShoulderDistanceLeft: result.metrics.earShoulderDistanceLeft,
            earShoulderDistanceRight: result.metrics.earShoulderDistanceRight,
            eyeShoulderDistanceLeft: result.metrics.eyeShoulderDistanceLeft,
            eyeShoulderDistanceRight: result.metrics.eyeShoulderDistanceRight,
            headForwardRatio: result.metrics.headForwardRatio,
            headTiltAngle: result.metrics.headTiltAngle,
            neckEarAngle: smoothed,
            headPitch: result.metrics.headPitch,
            faceSizeNormalized: result.metrics.faceSizeNormalized,
            shoulderEvenness: result.metrics.shoulderEvenness,
            earsVisible: result.metrics.earsVisible,
            landmarksDetected: result.metrics.landmarksDetected,
            forwardDepth: result.metrics.forwardDepth,
            irisGazeOffset: result.metrics.irisGazeOffset
        )

        // Calibration mode
        if calibrationManager.isCalibrating {
            if let calResult = calibrationManager.addSample(metrics, headPitch: metrics.headPitch) {
                calibrationMessage = calResult.message
                calibrationSuccess = calResult.isValid
                isCalibrating = false

                if calResult.isValid, let data = calResult.data {
                    calibrationData = data
                    // Store face baseline so face-based CVA estimation works (Vision fallback)
                    poseDetector.calibrateFaceBaseline()
                    notificationService.resetCooldown()
                    resetSuppressionState()
                    postureState = .initial
                    goodPostureStart = Date()
                }

                // Restore normal analysis interval
                scheduleAnalysis()
            }
            calibrationProgress = calibrationManager.progress
            return
        }

        // Normal monitoring
        if let baseline = calibrationData {
            // Full evaluation against calibrated baseline
            let previousSeverity = postureState.severity
            let newState = PostureAnalyzer.evaluate(
                metrics: metrics,
                baseline: baseline,
                previousState: postureState,
                cameraPosition: cameraPosition,
                yawDegrees: abs(currentHeadYaw),
                sensitivityMode: sensitivityMode
            )
            postureState = newState
            trackSlouchTransition(from: previousSeverity, to: newState.severity)

            // Track good posture duration — based on severity, not isTurtleNeck
            if newState.severity == .good {
                if goodPostureStart == nil {
                    goodPostureStart = Date()
                }
            } else {
                goodPostureStart = nil
            }

            // Send notification based on held severity with suppression gate
            let held = menuBarSeverity
            if held == .correction || held == .bad {
                // Suppress notifications for looking down / mixed (not real FHP)
                let classif = postureState.classification
                let pitchDrop = (calibrationData?.headPitch ?? 0) - lastMediaPipeHeadPitch
                let isLikelyLookingDown = classif == .lookingDown || classif == .mixed
                    || (classif == .forwardHead && pitchDrop > 4.0)  // pitch dropped >4° = head tilted down

                let shouldSuppress =
                    isLikelyLookingDown
                    || checkSustainedDurationGate()
                    || checkMotionSuppression(currentCVA: smoothed)
                    || checkScaleChangeSuppression(currentFaceSize: metrics.faceSizeNormalized)
                    || checkLandmarkJitterSuppression(nosePosition: result.joints.nose)
                    || checkWristProximitySuppression(joints: result.joints)

                if !shouldSuppress {
                    let msg = NotificationService.message(for: held)
                    notificationService.notify(
                        title: "PT Turtle",
                        message: msg,
                        severity: held
                    )
                }
            } else {
                sustainedBadStart = nil
            }
        } else {
            // No calibration yet - still show live CVA and severity from detection
            let severity = PostureAnalyzer.classifySeverity(
                metrics.neckEarAngle,
                mode: sensitivityMode
            )
            let previousSeverity = postureState.severity
            postureState = PostureState(
                badPostureStart: nil,
                isTurtleNeck: false,
                deviationScore: 0,
                usingFallback: !metrics.earsVisible,
                severity: severity,
                classification: .normal,
                currentCVA: metrics.neckEarAngle,
                baselineCVA: 0
            )
            trackSlouchTransition(from: previousSeverity, to: severity)
        }

        // Record score for rolling average (works with or without calibration)
        let score = PostureAnalyzer.cvaToScore(postureState.currentCVA)
        scoreHistory.append((date: now, score: score))
        recordSessionSample(score: score, cva: postureState.currentCVA)
        // Debug: log smoothed CVA, score, and severity every 3rd frame
        if Int.random(in: 0..<3) == 0 {
            let source = usingMediaPipe ? "MP" : "Vision"
            engineLog(String(format: "[SCORE/%@] rawCVA=%.1f smoothedCVA=%.1f score=%d severity=%@ menuBar=%@ pitch=%.1f",
                source, rawCVA, smoothed, score, postureState.severity.rawValue, menuBarSeverity.rawValue, lastMediaPipeHeadPitch))
        }
        // Prune entries older than 2 minutes
        let pruneDate = now.addingTimeInterval(-120)
        scoreHistory.removeAll { $0.date < pruneDate }

        // Update menu bar held severity with hold timer
        updateMenuBarSeverity(newSeverity: postureState.severity, currentCVA: postureState.currentCVA, now: now)

        lastError = nil
    }

    // MARK: - Notification Suppression

    private func checkSustainedDurationGate() -> Bool {
        // Returns true if should SUPPRESS (bad posture not sustained long enough)
        guard let start = sustainedBadStart else {
            sustainedBadStart = Date()
            return true  // just started, suppress
        }
        return Date().timeIntervalSince(start) < sustainedBadThreshold
    }

    private func checkMotionSuppression(currentCVA: CGFloat) -> Bool {
        guard let prev = previousSmoothedCVA else {
            previousSmoothedCVA = currentCVA
            return false
        }
        let delta = abs(currentCVA - prev)
        previousSmoothedCVA = currentCVA

        if delta > motionDeltaThreshold {
            motionSuppressed = true
            lowDeltaFrameCount = 0
            return true
        }

        if motionSuppressed {
            lowDeltaFrameCount += 1
            if lowDeltaFrameCount >= motionClearFrames {
                motionSuppressed = false
                lowDeltaFrameCount = 0
            }
            return motionSuppressed
        }
        return false
    }

    private func checkScaleChangeSuppression(currentFaceSize: CGFloat) -> Bool {
        let now = Date()
        defer { previousFaceSize = currentFaceSize }

        if let holdUntil = scaleChangeHoldUntil, now < holdUntil {
            return true
        }

        guard let prev = previousFaceSize, prev > 0 else { return false }
        let change = abs(currentFaceSize - prev) / prev
        if change > scaleChangeThreshold {
            scaleChangeHoldUntil = now.addingTimeInterval(scaleChangeHoldDuration)
            return true
        }
        return false
    }

    private func checkLandmarkJitterSuppression(nosePosition: CGPoint) -> Bool {
        let now = Date()

        if let holdUntil = jitterHoldUntil, now < holdUntil {
            return true
        }

        recentNosePositions.append((date: now, position: nosePosition))
        let cutoff = now.addingTimeInterval(-jitterWindowSeconds)
        recentNosePositions.removeAll { $0.date < cutoff }

        guard recentNosePositions.count >= 5 else { return false }

        let avgX = recentNosePositions.reduce(0.0) { $0 + $1.position.x } / CGFloat(recentNosePositions.count)
        let avgY = recentNosePositions.reduce(0.0) { $0 + $1.position.y } / CGFloat(recentNosePositions.count)
        let variance = recentNosePositions.reduce(0.0) { sum, entry in
            let dx = entry.position.x - avgX
            let dy = entry.position.y - avgY
            return sum + dx * dx + dy * dy
        } / CGFloat(recentNosePositions.count)

        if variance > jitterVarianceThreshold {
            jitterHoldUntil = now.addingTimeInterval(jitterHoldDuration)
            return true
        }
        return false
    }

    private func checkWristProximitySuppression(joints: DetectedJoints) -> Bool {
        let nose = joints.nose
        let wristProximityThreshold: CGFloat = 0.12

        if let lw = joints.leftWrist {
            let dx = lw.x - nose.x
            let dy = lw.y - nose.y
            if sqrt(dx * dx + dy * dy) < wristProximityThreshold { return true }
        }
        if let rw = joints.rightWrist {
            let dx = rw.x - nose.x
            let dy = rw.y - nose.y
            if sqrt(dx * dx + dy * dy) < wristProximityThreshold { return true }
        }
        return false
    }

    private func resetSuppressionState() {
        sustainedBadStart = nil
        previousSmoothedCVA = nil
        motionSuppressed = false
        lowDeltaFrameCount = 0
        previousFaceSize = nil
        scaleChangeHoldUntil = nil
        recentNosePositions.removeAll()
        jitterHoldUntil = nil
    }

    // MARK: - Session Tracking

    private func startSessionTracking() {
        resetSessionTracking()
        let now = Date()
        activeSessionID = UUID()
        sessionStartDate = now
        sessionLastTick = now
        sessionTotalSeconds = 0
        sessionGoodPostureSeconds = 0
        sessionScoreSum = 0
        sessionScoreSampleCount = 0
        sessionCVASum = 0
        sessionCVASampleCount = 0
        sessionSlouchEventCount = 0

        sessionSaveTimer = Timer.scheduledTimer(withTimeInterval: periodicSessionSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistSessionSnapshot(endDate: Date())
            }
        }
    }

    private func resetSessionTracking() {
        sessionSaveTimer?.invalidate()
        sessionSaveTimer = nil
        activeSessionID = nil
        sessionStartDate = nil
        sessionLastTick = nil
        sessionTotalSeconds = 0
        sessionGoodPostureSeconds = 0
        sessionScoreSum = 0
        sessionScoreSampleCount = 0
        sessionCVASum = 0
        sessionCVASampleCount = 0
        sessionSlouchEventCount = 0
    }

    private func updateSessionTrackingClock(now: Date) {
        guard activeSessionID != nil else { return }
        guard let lastTick = sessionLastTick else {
            sessionLastTick = now
            return
        }

        let delta = max(0, now.timeIntervalSince(lastTick))
        sessionTotalSeconds += delta
        if shouldCountAsGoodPosture {
            sessionGoodPostureSeconds += delta
        }
        sessionLastTick = now
    }

    private var shouldCountAsGoodPosture: Bool {
        calibrationData != nil &&
        !isCalibrating &&
        bodyDetected &&
        postureState.severity == .good
    }

    private func recordSessionSample(score: Int, cva: CGFloat) {
        guard activeSessionID != nil else { return }
        sessionScoreSum += Double(score)
        sessionScoreSampleCount += 1
        sessionCVASum += Double(cva)
        sessionCVASampleCount += 1
    }

    private func trackSlouchTransition(from previous: Severity, to current: Severity) {
        guard activeSessionID != nil else { return }
        guard previous != current else { return }
        if current == .bad || current == .away {
            sessionSlouchEventCount += 1
        }
    }

    private func persistSessionSnapshot(endDate: Date) {
        updateSessionTrackingClock(now: endDate)
        guard let record = buildSessionRecord(endDate: endDate) else { return }
        dataStore.saveSession(record)
    }

    private func buildSessionRecord(endDate: Date) -> SessionRecord? {
        guard let id = activeSessionID, let startDate = sessionStartDate else { return nil }

        let wallClockDuration = max(0, endDate.timeIntervalSince(startDate))
        let duration = max(sessionTotalSeconds, wallClockDuration)
        guard duration > 0 else { return nil }

        let averageScore = sessionScoreSampleCount > 0
            ? sessionScoreSum / Double(sessionScoreSampleCount)
            : Double(postureScore)

        let averageCVA = sessionCVASampleCount > 0
            ? sessionCVASum / Double(sessionCVASampleCount)
            : Double(postureState.currentCVA)

        let clampedGoodSeconds = min(duration, max(0, sessionGoodPostureSeconds))
        let goodPosturePercent = duration > 0 ? (clampedGoodSeconds / duration) * 100 : 0

        return SessionRecord(
            id: id,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            averageScore: max(0, min(100, averageScore)),
            goodPosturePercent: max(0, min(100, goodPosturePercent)),
            averageCVA: max(0, averageCVA),
            slouchEventCount: max(0, sessionSlouchEventCount)
        )
    }

    // MARK: - Menu Bar Severity Hold Timer

    /// Updates the held menu bar severity with asymmetric and stepped hold times:
    /// - Worsening: first change in ~1.5s, then shorter follow-up steps
    /// - Improving: first change in ~4.0s, then eased follow-up steps
    private func updateMenuBarSeverity(newSeverity: Severity, currentCVA: CGFloat, now: Date) {
        menuBarIsIdle = false

        guard newSeverity != menuBarSeverity else {
            // Current severity matches — clear any pending change
            pendingSeverity = nil
            pendingSeverityStart = nil
            pendingTransitionStepCount = 0
            return
        }

        guard shouldStartTransition(from: menuBarSeverity, toward: newSeverity, cva: currentCVA) else {
            pendingSeverity = nil
            pendingSeverityStart = nil
            pendingTransitionStepCount = 0
            return
        }

        guard pendingSeverity == newSeverity else {
            // New pending target — keep elapsed time if direction didn't reverse.
            if let existingPending = pendingSeverity {
                let existingDirectionIsWorsening = existingPending > menuBarSeverity
                let newDirectionIsWorsening = newSeverity > menuBarSeverity
                if existingDirectionIsWorsening == newDirectionIsWorsening {
                    pendingSeverity = newSeverity
                    if pendingSeverityStart == nil {
                        pendingSeverityStart = now
                    }
                    return
                }
            }

            pendingSeverity = newSeverity
            pendingSeverityStart = now
            pendingTransitionStepCount = 0
            return
        }

        guard let start = pendingSeverityStart else {
            pendingSeverityStart = now
            return
        }

        let isWorsening = newSeverity > menuBarSeverity
        let holdTime = holdDuration(isWorsening: isWorsening, stepCount: pendingTransitionStepCount)
        guard now.timeIntervalSince(start) >= holdTime else { return }

        let steppedSeverity = nextSeverityStep(from: menuBarSeverity, toward: newSeverity)
        menuBarSeverity = steppedSeverity

        if steppedSeverity == newSeverity {
            pendingSeverity = nil
            pendingSeverityStart = nil
            pendingTransitionStepCount = 0
        } else {
            pendingSeverityStart = now
            pendingTransitionStepCount += 1
        }
    }

    private func updateMenuBarForNoDetection(at now: Date) {
        guard let lastSuccessfulDetectionAt else { return }
        guard now.timeIntervalSince(lastSuccessfulDetectionAt) >= noDetectionIdleTimeout else { return }
        resetMenuBarForIdle()
    }

    private func resetMenuBarForIdle() {
        menuBarSeverity = .good
        menuBarIsIdle = true
        pendingSeverity = nil
        pendingSeverityStart = nil
        pendingTransitionStepCount = 0
        lastSuccessfulDetectionAt = nil
    }

    private func holdDuration(isWorsening: Bool, stepCount: Int) -> TimeInterval {
        if isWorsening {
            return stepCount == 0 ? worsenInitialHold : worsenFollowUpHold
        }
        return stepCount == 0 ? improveInitialHold : improveFollowUpHold
    }

    private func shouldStartTransition(from current: Severity, toward target: Severity, cva: CGFloat) -> Bool {
        guard let threshold = transitionThreshold(from: current, toward: target) else { return true }
        if abs(cva - threshold) <= cvaBoundaryBuffer { return false }
        if target > current {
            return cva <= threshold - cvaTransitionCrossover
        }
        return cva >= threshold + cvaTransitionCrossover
    }

    private func transitionThreshold(from current: Severity, toward target: Severity) -> CGFloat? {
        guard current != target else { return nil }

        if target > current {
            switch current {
            case .good: return PostureAnalyzer.cvaGood(for: sensitivityMode)
            case .correction: return PostureAnalyzer.cvaCorrection(for: sensitivityMode)
            case .bad: return PostureAnalyzer.cvaBad(for: sensitivityMode)
            case .away: return nil
            }
        }

        switch current {
        case .good: return nil
        case .correction: return PostureAnalyzer.cvaGood(for: sensitivityMode)
        case .bad: return PostureAnalyzer.cvaCorrection(for: sensitivityMode)
        case .away: return PostureAnalyzer.cvaBad(for: sensitivityMode)
        }
    }

    private func nextSeverityStep(from current: Severity, toward target: Severity) -> Severity {
        guard current != target else { return current }
        if target > current {
            switch current {
            case .good: return .correction
            case .correction: return .bad
            case .bad: return .away
            case .away: return .away
            }
        }

        switch current {
        case .good: return .good
        case .correction: return .good
        case .bad: return .correction
        case .away: return .bad
        }
    }

    // MARK: - Calibration

    func startCalibration() {
        calibrationManager.startCalibration()
        isCalibrating = true
        calibrationProgress = 0
        calibrationMessage = ""
        calibrationSuccess = nil

        if !isMonitoring {
            startMonitoring()
        } else {
            scheduleAnalysis()
        }
    }

    func resetCalibration() {
        calibrationManager.cancelCalibration()
        CalibrationManager.clearSaved()
        calibrationData = nil
        poseDetector.resetFaceBaseline()
        postureState = .initial
        isCalibrating = false
        calibrationProgress = 0
        calibrationMessage = ""
        calibrationSuccess = nil
        goodPostureStart = nil
        smoothedCVA = nil

        if isMonitoring {
            scheduleAnalysis()
        }
    }
}
