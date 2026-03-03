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
    @Published var monitoringInterval: TimeInterval = 3.0
    @Published var goodPostureStart: Date?
    @Published var lastError: String?
    @Published var currentFrame: CGImage?
    @Published var currentJoints: DetectedJoints?
    @Published var bodyDetected = false

    // Score history for 1-minute average
    private var scoreHistory: [(date: Date, score: Int)] = []

    // MARK: - Computed

    var postureScore: Int {
        PostureAnalyzer.cvaToScore(postureState.currentCVA)
    }

    var postureEmoji: String {
        PostureAnalyzer.scoreToEmoji(postureScore)
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

    enum IconState {
        case idle, good, mild, moderate, severe
    }

    var menuBarIconState: IconState {
        guard isMonitoring, calibrationData != nil else { return .idle }
        switch postureState.severity {
        case .good: return .good
        case .mild: return .mild
        case .moderate: return .moderate
        case .severe: return .severe
        }
    }

    // MARK: - Camera (public for session access if needed)

    let camera = CameraManager()

    // MARK: - Private

    private let poseDetector = VisionPoseDetector()
    private let calibrationManager = CalibrationManager()
    private let notificationService = NotificationService()
    private var analysisTimer: Timer?

    // Menu bar held severity — only changes after sustained threshold
    @Published private(set) var menuBarSeverity: Severity = .good
    private var pendingSeverity: Severity?
    private var pendingSeverityStart: Date?

    var menuBarStatusText: String {
        switch menuBarSeverity {
        case .good: return "Good"
        case .mild: return "Mild"
        case .moderate: return "Poor"
        case .severe: return "Bad"
        }
    }

    var menuBarStatusColor: String {
        switch menuBarSeverity {
        case .good: return "green"
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }

    // EMA smoothing for CVA — keep it simple, let raw signal through
    private var smoothedCVA: CGFloat? = nil
    private let emaAlpha: CGFloat = 0.5

    // Thread-safe frame storage
    private let frameLock = NSLock()
    private var _pendingFrame: CGImage?
    // Throttle UI updates to ~15fps to avoid overwhelming SwiftUI
    private var lastUIUpdate: Date = .distantPast
    private let uiUpdateInterval: TimeInterval = 1.0 / 15.0

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

        calibrationData = CalibrationManager.loadSaved()
        if let saved = UserDefaults.standard.string(forKey: "cameraPosition"),
           let pos = CameraPosition(rawValue: saved) {
            cameraPosition = pos
        }
        // Request all permissions upfront at app launch so dialogs don't
        // interrupt the popover later (macOS closes popovers on system dialogs).
        Task {
            _ = await CameraManager.requestPermission()
            notificationService.requestPermission()
        }

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
        engineLog("startMonitoring called")

        Task {
            do {
                try await camera.start()
                // Small delay for camera warmup
                try? await Task.sleep(nanoseconds: 300_000_000)
                scheduleAnalysis()
            } catch CameraManager.CameraError.notAuthorized {
                lastError = "Camera access denied. Enable in System Settings > Privacy."
                isMonitoring = false
            } catch {
                lastError = "Camera error: \(error.localizedDescription)"
                isMonitoring = false
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        analysisTimer?.invalidate()
        analysisTimer = nil
        camera.stop()
        currentFrame = nil
        currentJoints = nil
        bodyDetected = false
        smoothedCVA = nil
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    private func scheduleAnalysis() {
        analysisTimer?.invalidate()
        guard isMonitoring else { return }

        // Always analyze frequently for responsive skeleton/score updates
        // Face detection is lightweight enough for ~3fps analysis
        let interval: TimeInterval = isCalibrating ? 0.2 : 0.33
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
        guard let image = grabPendingFrame() else {
            if Int.random(in: 0..<30) == 0 { engineLog("no pending frame") }
            return
        }
        if Int.random(in: 0..<10) == 0 { engineLog("analyzing frame \(image.width)x\(image.height)") }

        do {
            guard let result = try poseDetector.detect(in: image) else {
                bodyDetected = false
                currentJoints = nil
                return
            }

            bodyDetected = true
            currentJoints = result.joints
            let rawCVA = result.metrics.neckEarAngle

            // Simple EMA smoothing — no special cases, just let the signal through.
            // Face fallback CVA=56 is a valid "good posture" reading, not a mask.
            let smoothed: CGFloat
            if let prev = smoothedCVA {
                smoothed = emaAlpha * rawCVA + (1 - emaAlpha) * prev
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
                shoulderEvenness: result.metrics.shoulderEvenness,
                earsVisible: result.metrics.earsVisible,
                landmarksDetected: result.metrics.landmarksDetected
            )

            // Calibration mode
            if calibrationManager.isCalibrating {
                if let calResult = calibrationManager.addSample(metrics) {
                    calibrationMessage = calResult.message
                    calibrationSuccess = calResult.isValid
                    isCalibrating = false

                    if calResult.isValid, let data = calResult.data {
                        calibrationData = data
                        // Store face baseline so face-based CVA estimation works
                        poseDetector.calibrateFaceBaseline()
                        notificationService.resetCooldown()
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
                let newState = PostureAnalyzer.evaluate(
                    metrics: metrics,
                    baseline: baseline,
                    previousState: postureState,
                    cameraPosition: cameraPosition
                )
                postureState = newState

                // Track good posture duration — based on severity, not isTurtleNeck
                if newState.severity == .good {
                    if goodPostureStart == nil {
                        goodPostureStart = Date()
                    }
                } else {
                    goodPostureStart = nil
                }

                // Send notification if sustained bad posture
                if newState.isTurtleNeck {
                    let msg = NotificationService.message(for: newState.severity)
                    notificationService.notify(
                        title: "Turtle Neck Alert!",
                        message: msg,
                        severity: newState.severity
                    )
                }
            } else {
                // No calibration yet - still show live CVA and severity from detection
                let severity = PostureAnalyzer.classifySeverity(metrics.neckEarAngle)
                postureState = PostureState(
                    badPostureStart: nil,
                    isTurtleNeck: false,
                    deviationScore: 0,
                    usingFallback: !metrics.earsVisible,
                    severity: severity,
                    currentCVA: metrics.neckEarAngle,
                    baselineCVA: 0
                )
            }

            // Record score for rolling average (works with or without calibration)
            let score = PostureAnalyzer.cvaToScore(postureState.currentCVA)
            let now2 = Date()
            scoreHistory.append((date: now2, score: score))
            // Debug: log smoothed CVA, score, and severity every 3rd frame
            if Int.random(in: 0..<3) == 0 {
                engineLog(String(format: "[SCORE] rawCVA=%.1f smoothedCVA=%.1f score=%d severity=%@ menuBar=%@",
                    rawCVA, smoothed, score, postureState.severity.rawValue, menuBarSeverity.rawValue))
            }
            // Prune entries older than 2 minutes
            let pruneDate = now2.addingTimeInterval(-120)
            scoreHistory.removeAll { $0.date < pruneDate }

            // Update menu bar held severity with hold timer
            updateMenuBarSeverity(newSeverity: postureState.severity, now: now2)

            lastError = nil
        } catch {
            // Silently ignore detection errors
        }
    }

    // MARK: - Menu Bar Severity Hold Timer

    /// Updates the held menu bar severity with asymmetric hold times:
    /// - Worsening (good→bad): 3 seconds hold
    /// - Improving (bad→good): 10 seconds hold
    private func updateMenuBarSeverity(newSeverity: Severity, now: Date) {
        guard newSeverity != menuBarSeverity else {
            // Current severity matches — clear any pending change
            pendingSeverity = nil
            pendingSeverityStart = nil
            return
        }

        let isWorsening = newSeverity > menuBarSeverity
        let holdTime: TimeInterval = isWorsening ? 3.0 : 10.0

        if pendingSeverity == newSeverity, let start = pendingSeverityStart {
            // Same pending severity — check if hold time elapsed
            if now.timeIntervalSince(start) >= holdTime {
                menuBarSeverity = newSeverity
                pendingSeverity = nil
                pendingSeverityStart = nil
            }
        } else {
            // New pending severity — start the timer
            pendingSeverity = newSeverity
            pendingSeverityStart = now
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
