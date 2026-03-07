import SwiftUI
import Combine
import os
import UserNotifications

enum MonitoringPowerState: String {
    case active
    case drowsy
    case inactive
}

enum PowerSavingSettings {
    static let autoPauseWhenAwayKey = "autoPauseWhenAway"
    static let inactiveTimeoutSecondsKey = "inactiveTimeoutSeconds"
    static let defaultAutoPauseWhenAway = true
    static let defaultInactiveTimeoutSeconds: Double = 30
    static let minInactiveTimeoutSeconds: Double = 30
    static let maxInactiveTimeoutSeconds: Double = 300
}

enum CameraSelectionSettings {
    static let cameraSourceModeKey = "cameraSourceMode"
    static let manualCameraDeviceIDKey = "manualCameraDeviceID"
    static let cameraContextSelectionKey = "cameraContextSelection"
}

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
    @Published var powerState: MonitoringPowerState = .active
    @Published var cameraSourceMode: CameraSourceMode = .auto {
        didSet {
            persistCameraSourceModeIfNeeded()
            applyCameraSelectionIfMonitoring()
        }
    }
    @Published var manualCameraDeviceID = "" {
        didSet {
            persistManualCameraDeviceIDIfNeeded()
            applyCameraSelectionIfMonitoring()
        }
    }
    @Published var cameraContextSelection: CameraContextSelection = .auto {
        didSet {
            persistCameraContextSelectionIfNeeded()
        }
    }
    @Published var availableCameraDevices: [CameraDeviceOption] = []
    @Published var activeCameraDisplayName = "No active camera"
    @Published private(set) var inferredCameraContext: CameraContext = .unknown
    @Published private(set) var inferredContextConfidence: CGFloat = 0
    @Published private(set) var inferredFramingState: FramingState = .checking
    @Published private(set) var inferredContextSource: String = "auto"
    @AppStorage(SensitivityMode.storageKey)
    private var sensitivityModeRawValue = SensitivityMode.defaultMode.rawValue
    @AppStorage(CameraSelectionSettings.cameraSourceModeKey)
    private var cameraSourceModeRawValue = CameraSourceMode.auto.rawValue {
        didSet { syncCameraSourceModeFromStorage() }
    }
    @AppStorage(CameraSelectionSettings.manualCameraDeviceIDKey)
    private var storedManualCameraDeviceID = "" {
        didSet { syncManualCameraDeviceIDFromStorage() }
    }
    @AppStorage(CameraSelectionSettings.cameraContextSelectionKey)
    private var cameraContextSelectionRawValue = CameraContextSelection.auto.rawValue {
        didSet { syncCameraContextSelectionFromStorage() }
    }
    @AppStorage(PowerSavingSettings.autoPauseWhenAwayKey)
    private var autoPauseEnabled = PowerSavingSettings.defaultAutoPauseWhenAway {
        didSet { handleAutoPauseSettingChanged() }
    }
    @AppStorage(PowerSavingSettings.inactiveTimeoutSecondsKey)
    private var inactiveTimeout = PowerSavingSettings.defaultInactiveTimeoutSeconds {
        didSet { handleInactiveTimeoutChanged() }
    }
    @AppStorage("adaptiveContextLogOnlyEnabled")
    private var adaptiveContextLogOnlyEnabled = true

    // Score history for 1-minute average
    private var scoreHistory: [(date: Date, score: Int)] = []
    private var lastContextInference: CameraContextInference?
    private var lastContextLogAt: Date = .distantPast
    private let contextLogInterval: TimeInterval = 2.0

    // MARK: - Computed

    var postureScore: Int {
        postureState.score
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
    // Set notification delegate in init or wherever the engine initializes
    private var analysisTimer: Timer?
    private var probeTimer: Timer?
    private var probeTask: Task<Void, Never>?
    private var noDetectionStart: Date?
    private var consecutiveDetections = 0
    private let activeAnalysisInterval: TimeInterval = 0.33
    private let drowsyAnalysisInterval: TimeInterval = 2.0
    private let calibrationAnalysisInterval: TimeInterval = 0.2
    private let inactiveProbeInterval: TimeInterval = 6.0
    private let inactiveProbeWarmup: TimeInterval = 1.5
    private var useMediaPipe = true  // prefer MediaPipe, fallback to Vision
    private var mediaPipeConnectAttempted = false
    private var isMediaPipeConnectInFlight = false
    private var mediaPipeConnectTask: Task<Void, Never>?
    private var lastMediaPipeConnectAttemptAt: Date = .distantPast
    private let mediaPipeReconnectCooldown: TimeInterval = 5.0
    private var isAnalysisInFlight = false
    private var lastMediaPipeHeadPitch: CGFloat = 0
    #if DEBUG
    private struct StartupPerfState {
        let startedAt: Date
        var firstFrameAt: Date?
        var mediaPipeConnectedAt: Date?
        var firstScoreAt: Date?
        var firstScoreSource: String?
        var calibrationCompletedAt: Date?
        var analysisDrops = 0
    }
    private var startupPerfState: StartupPerfState?
    #endif
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
    private let scoreBoundaryBuffer: Int = 3
    private let scoreTransitionCrossover: Int = 5

    #if DEBUG
    // MARK: - Debug Capture
    private enum DebugEyeClass: String {
        case forwardHead
        case lookingDown
        case inconclusive
        case fallback
        case skip
    }

    private struct DebugEyeSample {
        let date: Date
        let eyeClass: DebugEyeClass
        let confidence: Double
        let reason: String
    }

    private let debugEyeMajorityConfidenceThreshold: Double = 0.70

    @Published var debugCaptureLabel: String?
    private var debugCaptureStart: Date?
    private let debugCaptureDuration: TimeInterval = 5.0
    private var debugSnapshotTimer: Timer?
    private var debugSnapshotCount = 0
    private var debugCaptureLogOffset: UInt64?
    private var debugEyeSamples: [DebugEyeSample] = []
    private let debugLogPath = "/tmp/turtle_cvadebug.log"

    func startDebugCapture(label: String) {
        debugCaptureLabel = label
        debugCaptureStart = Date()
        debugSnapshotCount = 0
        debugCaptureLogOffset = currentDebugLogOffset()
        debugEyeSamples.removeAll(keepingCapacity: true)
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
        if let summary = summarizeDebugCapture(label: label) {
            appendToDebugLog(summary + "\n")
        }
        debugCaptureLabel = nil
        debugCaptureStart = nil
        debugCaptureLogOffset = nil
        debugEyeSamples.removeAll(keepingCapacity: true)
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
        #if DEBUG
        DebugLogWriter.append(text)
        #endif
    }

    private func currentDebugLogOffset() -> UInt64? {
        let url = URL(fileURLWithPath: debugLogPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.uint64Value
    }

    private func summarizeDebugCapture(label: String) -> String? {
        let url = URL(fileURLWithPath: debugLogPath)
        guard let offset = debugCaptureLogOffset,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }

            var classCounts: [String: Int] = [:]
            var evalScores: [Int] = []
            var evalClasses: [String] = []
            for line in text.split(separator: "\n").map(String.init) where line.contains("[EVAL]") {
                if let cls = captureGroup(in: line, pattern: "class=([^ ]+)") {
                    classCounts[cls, default: 0] += 1
                    evalClasses.append(cls)
                }
                if let scoreText = captureGroup(in: line, pattern: "relScore=([0-9]+)"),
                   let score = Int(scoreText) {
                    evalScores.append(score)
                }
            }

            let eyeWindowStart = (debugCaptureStart ?? Date()).addingTimeInterval(-debugCaptureDuration)
            let eyeWindowSamples = debugEyeSamples.filter { $0.date >= eyeWindowStart }
            let eyeCounts = Dictionary(grouping: eyeWindowSamples, by: \.eyeClass.rawValue).mapValues(\.count)
            let usableEyeSamples = eyeWindowSamples.filter { $0.eyeClass != .skip }
            let decisiveEyeSamples = usableEyeSamples.filter {
                ($0.eyeClass == .forwardHead || $0.eyeClass == .lookingDown) &&
                $0.confidence >= debugEyeMajorityConfidenceThreshold
            }
            let decisiveEyeCounts = Dictionary(grouping: decisiveEyeSamples, by: \.eyeClass.rawValue).mapValues(\.count)
            let skipReasonCounts = Dictionary(
                grouping: eyeWindowSamples.filter { $0.eyeClass == .skip },
                by: \.reason
            ).mapValues(\.count)

            guard !classCounts.isEmpty || !eyeCounts.isEmpty else { return nil }

            let classText = formatCountSummary(classCounts)
            let eyeText = eyeCounts.isEmpty ? "n/a" : formatCountSummary(eyeCounts)
            let majorityEyeClass = decisiveEyeCounts.max {
                if $0.value == $1.value { return $0.key > $1.key }
                return $0.value < $1.value
            }
            let majorityText = majorityEyeClass.map { "\($0.key):\($0.value)" } ?? "n/a"
            let avgEyeConf = decisiveEyeSamples.isEmpty
                ? "n/a"
                : String(format: "%.2f", decisiveEyeSamples.reduce(0.0) { $0 + $1.confidence } / Double(decisiveEyeSamples.count))
            let avgEyeConfAll = usableEyeSamples.isEmpty
                ? "n/a"
                : String(format: "%.2f", usableEyeSamples.reduce(0.0) { $0 + $1.confidence } / Double(usableEyeSamples.count))
            let skipText = skipReasonCounts.isEmpty ? "none" : formatCountSummary(skipReasonCounts)
            let scoreSummary = summarizeDebugScores(scores: evalScores, classes: evalClasses)
            return "[DEBUG SUMMARY] label=\(label) class=\(classText) scoreAvg=\(scoreSummary.scoreAvg) scoreHoldAvg=\(scoreSummary.scoreHoldAvg) scoreLowAvg=\(scoreSummary.scoreLowAvg) scoreMin=\(scoreSummary.scoreMin) holdClass=\(scoreSummary.holdClass) eyeWindow=5.0s eyeSamples=\(eyeWindowSamples.count) eyeUsable=\(usableEyeSamples.count) eyeMajorityUsable=\(decisiveEyeSamples.count) eyeMajorityConfMin=\(String(format: "%.2f", debugEyeMajorityConfidenceThreshold)) eyeMajority=\(majorityText) eyeConfAvg=\(avgEyeConf) eyeConfAvgAll=\(avgEyeConfAll) eyeClass=\(eyeText) eyeSkip=\(skipText)"
        } catch {
            return nil
        }
    }

    private func summarizeDebugScores(scores: [Int], classes: [String]) -> (
        scoreAvg: String,
        scoreHoldAvg: String,
        scoreLowAvg: String,
        scoreMin: String,
        holdClass: String
    ) {
        guard !scores.isEmpty else {
            return ("n/a", "n/a", "n/a", "n/a", "n/a")
        }

        let avg = String(format: "%.1f", Double(scores.reduce(0, +)) / Double(scores.count))
        let minScore = String(scores.min() ?? 0)

        let lowerCount = max(1, scores.count / 3)
        let lowBand = scores.sorted().prefix(lowerCount)
        let lowAvg = String(format: "%.1f", Double(lowBand.reduce(0, +)) / Double(lowBand.count))

        let start = scores.count / 4
        let end = max(start + 1, scores.count - start)
        let holdScores = Array(scores[start..<end])
        let holdAvg = String(format: "%.1f", Double(holdScores.reduce(0, +)) / Double(holdScores.count))

        let holdClasses: [String]
        if classes.count == scores.count {
            holdClasses = Array(classes[start..<end])
        } else {
            holdClasses = classes
        }
        let holdClassCounts = Dictionary(grouping: holdClasses, by: { $0 }).mapValues(\.count)
        let holdClass = holdClassCounts.max {
            if $0.value == $1.value { return $0.key > $1.key }
            return $0.value < $1.value
        }?.key ?? "n/a"

        return (avg, holdAvg, lowAvg, minScore, holdClass)
    }

    private func recordDebugEyeSampleIfNeeded(
        metrics: PostureMetrics,
        baseline: CalibrationData?,
        usingMediaPipe: Bool,
        yawDegrees: CGFloat,
        now: Date
    ) {
        guard debugCaptureLabel != nil else { return }

        let sample = classifyDebugEyeSample(
            metrics: metrics,
            baseline: baseline,
            usingMediaPipe: usingMediaPipe,
            yawDegrees: yawDegrees
        )
        debugEyeSamples.append(DebugEyeSample(
            date: now,
            eyeClass: sample.eyeClass,
            confidence: sample.confidence,
            reason: sample.reason
        ))

        let cutoff = now.addingTimeInterval(-debugCaptureDuration)
        if debugEyeSamples.count > 32 {
            debugEyeSamples.removeAll { $0.date < cutoff }
        }
    }

    private func classifyDebugEyeSample(
        metrics: PostureMetrics,
        baseline: CalibrationData?,
        usingMediaPipe: Bool,
        yawDegrees: CGFloat
    ) -> (eyeClass: DebugEyeClass, confidence: Double, reason: String) {
        guard cameraPosition == .center else {
            return (.skip, 0, "nonCenterCamera")
        }
        guard let baseline else {
            return (.skip, 0, "noBaseline")
        }
        guard baseline.schemaVersion >= 2, baseline.baselineFaceSize > 0.0001 else {
            return (.skip, 0, "unsupportedBaseline")
        }
        guard yawDegrees < 20 else {
            return (.skip, 0, "highYaw")
        }
        guard metrics.landmarksDetected else {
            return (.skip, 0, "noLandmarks")
        }
        guard usingMediaPipe else {
            return (.fallback, 0.25, "visionFallback")
        }

        let irisGazeDelta = metrics.irisGazeOffset - baseline.irisGazeOffset

        let result = PostureClassifier.classifyEyeLevelForwardHeadVsLookingDown(
            cvaDrop: baseline.neckEarAngle - metrics.neckEarAngle,
            pitchDrop: baseline.headPitch - metrics.headPitch,
            faceSizeChange: (metrics.faceSizeNormalized - baseline.baselineFaceSize) / baseline.baselineFaceSize,
            depthIncrease: metrics.forwardDepth - baseline.forwardDepth,
            yawDegrees: yawDegrees,
            irisGazeOffset: irisGazeDelta
        )

        switch result.classification {
        case .forwardHead:
            return (.forwardHead, Double(result.confidence), "narrowHelper")
        case .lookingDown:
            return (.lookingDown, Double(result.confidence), "narrowHelper")
        case .inconclusive:
            return (.inconclusive, Double(result.confidence), "narrowHelper")
        }
    }

    private func captureGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[matchRange])
    }

    private func formatCountSummary(_ counts: [String: Int]) -> String {
        counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }
    #endif

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
        if isMonitoring {
            switch powerState {
            case .drowsy:
                return "Low Power"
            case .inactive:
                return "Paused"
            case .active:
                break
            }
        }
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
    private var sessionBadPostureSeconds: TimeInterval = 0
    private var sessionResetCount = 0
    private var sessionLongestSlouchSeconds: TimeInterval = 0
    private var sessionCurrentSlouchStart: Date?
    private var isSyncingCameraSelectionState = false
    private var isSyncingCameraContextSelectionState = false

    // MARK: - Init

    init() {
        UNUserNotificationCenter.current().delegate = notificationService
        UserDefaults.standard.register(defaults: [
            PowerSavingSettings.autoPauseWhenAwayKey: PowerSavingSettings.defaultAutoPauseWhenAway,
            PowerSavingSettings.inactiveTimeoutSecondsKey: PowerSavingSettings.defaultInactiveTimeoutSeconds,
            CameraSelectionSettings.cameraSourceModeKey: CameraSourceMode.auto.rawValue,
            CameraSelectionSettings.manualCameraDeviceIDKey: "",
            CameraSelectionSettings.cameraContextSelectionKey: CameraContextSelection.auto.rawValue,
            "adaptiveContextLogOnlyEnabled": true
        ])
        handleInactiveTimeoutChanged()

        #if DEBUG
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
        #endif

        // Warm-start from the last saved calibration so we can score quickly,
        // then refresh it on monitor start for the current session.
        calibrationData = CalibrationManager.loadSaved()
        if let saved = UserDefaults.standard.string(forKey: "cameraPosition"),
           let pos = CameraPosition(rawValue: saved) {
            cameraPosition = pos
        }
        loadCameraSelectionSettings()
        refreshCameraDevices()
        // Notification permission is requested after camera starts in OnboardingView.

        // Frame callback runs on camera's background queue
        // CameraManager already rotates portrait frames to landscape
        camera.onFrame = { [weak self] image in
            guard let self else { return }
            // Store for analysis
            self.frameLock.lock()
            self._pendingFrame = image
            self.frameLock.unlock()

            #if DEBUG
            if self.startupPerfState?.firstFrameAt == nil {
                let now = Date()
                self.startupPerfState?.firstFrameAt = now
                if let startedAt = self.startupPerfState?.startedAt {
                    self.engineLog(String(
                        format: "[PERF_START] firstFrameMs=%.1f",
                        now.timeIntervalSince(startedAt) * 1000
                    ))
                }
            }
            #endif

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
        #if DEBUG
        DebugLogWriter.append("\(Date()): [ENGINE] \(msg)\n")
        #endif
    }

    private func scheduleMediaPipeConnectIfNeeded(logFailure: Bool) {
        guard useMediaPipe, isMonitoring else { return }
        guard !isMediaPipeConnectInFlight else { return }

        let now = Date()
        guard now.timeIntervalSince(lastMediaPipeConnectAttemptAt) >= mediaPipeReconnectCooldown else { return }

        mediaPipeConnectAttempted = true
        isMediaPipeConnectInFlight = true
        lastMediaPipeConnectAttemptAt = now

        mediaPipeConnectTask?.cancel()
        mediaPipeConnectTask = Task { [weak self] in
            guard let self else { return }
            let connected = await self.mediaPipeClient.connectAsync()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.isMediaPipeConnectInFlight = false
                self.mediaPipeConnectTask = nil
                guard self.isMonitoring else { return }

                if connected {
                    #if DEBUG
                    let now = Date()
                    self.startupPerfState?.mediaPipeConnectedAt = now
                    if let startedAt = self.startupPerfState?.startedAt {
                        self.engineLog(String(
                            format: "[PERF_START] mediaPipeConnectedMs=%.1f",
                            now.timeIntervalSince(startedAt) * 1000
                        ))
                    }
                    #endif
                    self.engineLog("MediaPipe server connected — using enhanced detection")
                } else if logFailure {
                    self.engineLog("MediaPipe server unavailable — falling back to Vision framework")
                }
            }
        }
    }

    private func grabPendingFrame() -> CGImage? {
        frameLock.lock()
        let frame = _pendingFrame
        frameLock.unlock()
        return frame
    }

    private var resolvedManualCameraDeviceID: String? {
        let trimmed = manualCameraDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func refreshCameraDevices() {
        availableCameraDevices = CameraManager.discoverVideoDevices()

        if let manualID = resolvedManualCameraDeviceID,
           !availableCameraDevices.contains(where: { $0.id == manualID }) {
            manualCameraDeviceID = ""
        }
        refreshActiveCameraDisplayName()
    }

    func cameraDeviceID(for option: CameraDeviceOption) -> String {
        option.id
    }

    func cameraDeviceDisplayName(for option: CameraDeviceOption) -> String {
        option.displayName
    }

    private func persistCameraSourceModeIfNeeded() {
        guard !isSyncingCameraSelectionState else { return }
        if cameraSourceModeRawValue != cameraSourceMode.rawValue {
            cameraSourceModeRawValue = cameraSourceMode.rawValue
        }
        refreshActiveCameraDisplayName()
    }

    private func persistManualCameraDeviceIDIfNeeded() {
        guard !isSyncingCameraSelectionState else { return }
        if storedManualCameraDeviceID != manualCameraDeviceID {
            storedManualCameraDeviceID = manualCameraDeviceID
        }
        refreshActiveCameraDisplayName()
    }

    private func syncCameraSourceModeFromStorage() {
        guard !isSyncingCameraSelectionState else { return }
        let resolvedMode = CameraSourceMode(rawValue: cameraSourceModeRawValue) ?? .auto
        guard cameraSourceMode != resolvedMode else { return }
        isSyncingCameraSelectionState = true
        cameraSourceMode = resolvedMode
        isSyncingCameraSelectionState = false
        refreshActiveCameraDisplayName()
    }

    private func syncManualCameraDeviceIDFromStorage() {
        guard !isSyncingCameraSelectionState else { return }
        guard manualCameraDeviceID != storedManualCameraDeviceID else { return }
        isSyncingCameraSelectionState = true
        manualCameraDeviceID = storedManualCameraDeviceID
        isSyncingCameraSelectionState = false
        refreshActiveCameraDisplayName()
    }

    private func persistCameraContextSelectionIfNeeded() {
        guard !isSyncingCameraContextSelectionState else { return }
        if cameraContextSelectionRawValue != cameraContextSelection.rawValue {
            cameraContextSelectionRawValue = cameraContextSelection.rawValue
        }
    }

    private func syncCameraContextSelectionFromStorage() {
        guard !isSyncingCameraContextSelectionState else { return }
        let resolved = CameraContextSelection(rawValue: cameraContextSelectionRawValue) ?? .auto
        guard cameraContextSelection != resolved else { return }
        isSyncingCameraContextSelectionState = true
        cameraContextSelection = resolved
        isSyncingCameraContextSelectionState = false
    }

    private func loadCameraSelectionSettings() {
        isSyncingCameraSelectionState = true
        cameraSourceMode = CameraSourceMode(rawValue: cameraSourceModeRawValue) ?? .auto
        manualCameraDeviceID = storedManualCameraDeviceID
        isSyncingCameraSelectionState = false

        isSyncingCameraContextSelectionState = true
        cameraContextSelection = CameraContextSelection(rawValue: cameraContextSelectionRawValue) ?? .auto
        isSyncingCameraContextSelectionState = false

        if cameraSourceModeRawValue != cameraSourceMode.rawValue {
            cameraSourceModeRawValue = cameraSourceMode.rawValue
        }
        if cameraContextSelectionRawValue != cameraContextSelection.rawValue {
            cameraContextSelectionRawValue = cameraContextSelection.rawValue
        }
    }

    private func refreshActiveCameraDisplayName() {
        if let active = camera.activeDevice {
            activeCameraDisplayName = active.displayName
            return
        }

        if let manualID = resolvedManualCameraDeviceID,
           let selected = availableCameraDevices.first(where: { $0.id == manualID }) {
            activeCameraDisplayName = "\(selected.displayName) (selected)"
            return
        }

        activeCameraDisplayName = "No active camera"
    }

    private func applyCameraSelectionIfMonitoring() {
        guard isMonitoring else { return }
        Task {
            do {
                try await camera.start(
                    sourceMode: cameraSourceMode,
                    manualDeviceID: resolvedManualCameraDeviceID
                )
                refreshCameraDevices()
            } catch {
                lastError = "Camera error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        resetPowerManagementState()
        isMonitoring = true
        #if DEBUG
        startupPerfState = StartupPerfState(startedAt: Date())
        #endif
        lastError = nil
        resetMenuBarForIdle()
        startSessionTracking()
        refreshCameraDevices()
        engineLog("startMonitoring called")

        Task {
            do {
                try await camera.start(sourceMode: cameraSourceMode, manualDeviceID: resolvedManualCameraDeviceID)
                refreshActiveCameraDisplayName()
                // Small delay for camera warmup
                try? await Task.sleep(nanoseconds: 300_000_000)

                // Connect to MediaPipe in the background so monitor start doesn't block the UI.
                if useMediaPipe && !mediaPipeConnectAttempted {
                    scheduleMediaPipeConnectIfNeeded(logFailure: true)
                }

                scheduleAnalysis()

                // Auto-calibrate on every start so baseline matches current session
                startCalibration()
            } catch CameraManager.CameraError.notAuthorized {
                lastError = "Camera access denied. Open System Settings → Privacy & Security → Camera and enable Turtleneck Coach."
                isMonitoring = false
                isCalibrating = false
                refreshActiveCameraDisplayName()
                calibrationManager.cancelCalibration()
                resetSessionTracking()
            } catch {
                lastError = "Camera error: \(error.localizedDescription)"
                isMonitoring = false
                isCalibrating = false
                refreshActiveCameraDisplayName()
                calibrationManager.cancelCalibration()
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
        resetPowerManagementState()
        camera.stopSession()
        refreshActiveCameraDisplayName()
        mediaPipeClient.disconnect()
        mediaPipeConnectAttempted = false
        isMediaPipeConnectInFlight = false
        mediaPipeConnectTask?.cancel()
        mediaPipeConnectTask = nil
        currentFrame = nil
        currentJoints = nil
        bodyDetected = false
        smoothedCVA = nil
        resetSuppressionState()
        resetMenuBarForIdle()
        #if DEBUG
        startupPerfState = nil
        #endif
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

    private var powerStateManagementEnabled: Bool {
        autoPauseEnabled && !isCalibrating
    }

    private var inactiveTimeoutInterval: TimeInterval {
        max(PowerSavingSettings.minInactiveTimeoutSeconds, inactiveTimeout)
    }

    private var drowsyTimeoutInterval: TimeInterval {
        inactiveTimeoutInterval * 0.5
    }

    private var currentAnalysisInterval: TimeInterval {
        if isCalibrating { return calibrationAnalysisInterval }
        if !autoPauseEnabled { return activeAnalysisInterval }
        switch powerState {
        case .active:
            return activeAnalysisInterval
        case .drowsy:
            return drowsyAnalysisInterval
        case .inactive:
            return activeAnalysisInterval
        }
    }

    private func scheduleAnalysis(runImmediately: Bool = true) {
        analysisTimer?.invalidate()
        guard isMonitoring, powerState != .inactive else { return }

        let interval = currentAnalysisInterval
        analysisTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.analyzeLatestFrame()
            }
        }
        if runImmediately {
            Task { @MainActor [weak self] in
                await self?.analyzeLatestFrame()
            }
        }
    }

    // MARK: - Analyze

    private func analyzeLatestFrame(isProbe: Bool = false) async {
        guard !isAnalysisInFlight else {
            #if DEBUG
            startupPerfState?.analysisDrops += 1
            #endif
            return
        }
        isAnalysisInFlight = true
        defer { isAnalysisInFlight = false }

        if isProbe {
            engineLog("running inactive probe analysis")
        }
        let now = Date()
        updateSessionTrackingClock(now: now)

        if isCalibrating && powerState != .active {
            transitionPowerState(to: .active, reason: "calibration requires active mode")
        } else if !autoPauseEnabled && powerState != .active {
            transitionPowerState(to: .active, reason: "auto-pause disabled")
        }

        guard let image = grabPendingFrame() else {
            if Int.random(in: 0..<30) == 0 { engineLog("no pending frame") }
            updateMenuBarForNoDetection(at: now)
            handleNoDetection(at: now)
            return
        }
        if Int.random(in: 0..<10) == 0 { engineLog("analyzing frame \(image.width)x\(image.height)") }

        // Try MediaPipe first, then fall back to Vision framework
        let detectionResult: DetectionResult?
        let usingMediaPipe: Bool

        if useMediaPipe && mediaPipeClient.isConnected,
           let mpResult = await mediaPipeClient.sendFrameAsync(image),
           mpResult.confidence > 0.1 {
            // MediaPipe path — convert result to DetectionResult
            let joints = mediaPipeClient.resultToJoints(mpResult)
            let metrics = mediaPipeClient.resultToMetrics(mpResult, imageWidth: image.width, imageHeight: image.height)
            detectionResult = DetectionResult(metrics: metrics, joints: joints)
            lastMediaPipeHeadPitch = CGFloat(mpResult.headPitch)
            setCurrentHeadPoseIfNeeded(
                pitch: CGFloat(mpResult.headPitch),
                yaw: CGFloat(mpResult.headYaw)
            )
            usingMediaPipe = true
        } else {
            // Vision framework fallback
            detectionResult = try? await poseDetector.detectAsync(in: image)
            usingMediaPipe = false

            // Reconnect in the background with cooldown so fallback frames do not block the UI.
            if useMediaPipe && !mediaPipeClient.isConnected {
                scheduleMediaPipeConnectIfNeeded(logFailure: false)
            }
        }

        guard let result = detectionResult else {
            setDetectionState(bodyDetected: false, joints: nil)
            updateMenuBarForNoDetection(at: now)
            handleNoDetection(at: now)
            return
        }

        handleDetectionSuccess()
        setDetectionState(bodyDetected: true, joints: result.joints)
        lastSuccessfulDetectionAt = now
        setMenuBarIdleIfNeeded(false)
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
        updateCameraContextInference(
            metrics: metrics,
            baseline: calibrationData,
            noseY: result.joints.nose.y,
            now: now
        )
        #if DEBUG
        recordDebugEyeSampleIfNeeded(
            metrics: metrics,
            baseline: calibrationData,
            usingMediaPipe: usingMediaPipe,
            yawDegrees: abs(currentHeadYaw),
            now: now
        )
        #endif

        // Calibration mode
        if calibrationManager.isCalibrating {
            if let calResult = calibrationManager.addSample(metrics, headPitch: metrics.headPitch) {
                calibrationMessage = calResult.message
                calibrationSuccess = calResult.isValid
                isCalibrating = false
                #if DEBUG
                let now = Date()
                startupPerfState?.calibrationCompletedAt = now
                if let startedAt = startupPerfState?.startedAt {
                    engineLog(String(
                        format: "[PERF_START] calibrationCompletedMs=%.1f",
                        now.timeIntervalSince(startedAt) * 1000
                    ))
                }
                #endif

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
            if calibrationData == nil {
                return
            }
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
            trackSlouchTransition(from: previousSeverity, to: newState.severity, at: now)

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
                        title: msg.title,
                        message: msg.body,
                        severity: held
                    )
                }
            } else {
                sustainedBadStart = nil
            }
        } else {
            // No calibration yet - show neutral score until calibration completes
            let preCalibScore = 50
            let severity = PostureAnalyzer.classifySeverity(
                score: preCalibScore,
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
                baselineCVA: 0,
                score: preCalibScore
            )
            trackSlouchTransition(from: previousSeverity, to: severity, at: now)
        }

        // Record score for rolling average (works with or without calibration)
        let score = postureState.score
        scoreHistory.append((date: now, score: score))
        recordSessionSample(score: score, cva: postureState.currentCVA)
        #if DEBUG
        if startupPerfState?.firstScoreAt == nil {
            startupPerfState?.firstScoreAt = now
            startupPerfState?.firstScoreSource = usingMediaPipe ? "mp" : "vision"
            if let perf = startupPerfState {
                let firstFrameMs = perf.firstFrameAt.map { $0.timeIntervalSince(perf.startedAt) * 1000 } ?? -1
                let mpConnectMs = perf.mediaPipeConnectedAt.map { $0.timeIntervalSince(perf.startedAt) * 1000 } ?? -1
                engineLog(String(
                    format: "[PERF_START] firstScoreMs=%.1f source=%@ firstFrameMs=%.1f mediaPipeConnectedMs=%.1f analysisDrops=%d",
                    now.timeIntervalSince(perf.startedAt) * 1000,
                    perf.firstScoreSource ?? "unknown",
                    firstFrameMs,
                    mpConnectMs,
                    perf.analysisDrops
                ))
            }
        }
        #endif
        // Debug: log smoothed CVA, score, and severity every 3rd frame
        if Int.random(in: 0..<3) == 0 {
            let source = usingMediaPipe ? "MP" : "Vision"
            engineLog(String(format: "[SCORE/%@] rawCVA=%.1f smoothedCVA=%.1f relScore=%d severity=%@ menuBar=%@ pitch=%.1f",
                source, rawCVA, smoothed, score, postureState.severity.rawValue, menuBarSeverity.rawValue, lastMediaPipeHeadPitch))
        }
        // Prune entries older than 2 minutes
        let pruneDate = now.addingTimeInterval(-120)
        scoreHistory.removeAll { $0.date < pruneDate }

        // Update menu bar held severity with hold timer
        updateMenuBarSeverity(newSeverity: postureState.severity, currentScore: score, now: now)

        lastError = nil
    }

    // MARK: - Camera Context Inference (Phase 1: log-only)

    private func updateCameraContextInference(
        metrics: PostureMetrics,
        baseline: CalibrationData?,
        noseY: CGFloat,
        now: Date
    ) {
        let inference = inferCameraContext(metrics: metrics, baseline: baseline, noseY: noseY)

        // Avoid triggering SwiftUI updates on every frame when the inferred
        // context is effectively unchanged.
        if inferredCameraContext != inference.context {
            inferredCameraContext = inference.context
        }
        if abs(inferredContextConfidence - inference.confidence) >= 0.01 {
            inferredContextConfidence = inference.confidence
        }
        if inferredFramingState != inference.framingState {
            inferredFramingState = inference.framingState
        }
        if inferredContextSource != inference.source {
            inferredContextSource = inference.source
        }

        guard adaptiveContextLogOnlyEnabled else {
            lastContextInference = inference
            return
        }

        let previous = lastContextInference
        let contextChanged =
            previous?.context != inference.context ||
            previous?.framingState != inference.framingState ||
            previous?.source != inference.source
        let confidenceChanged = abs((previous?.confidence ?? -1) - inference.confidence) >= 0.15
        let periodicLogDue = now.timeIntervalSince(lastContextLogAt) >= contextLogInterval

        guard contextChanged || confidenceChanged || periodicLogDue else { return }

        let confText = String(format: "%.2f", inference.confidence)
        let ratioText = inference.faceSizeRatio > 0 ? String(format: "%.2f", inference.faceSizeRatio) : "n/a"
        let camName = camera.activeDevice?.displayName ?? activeCameraDisplayName
        let camModel = camera.activeDevice?.modelID ?? "n/a"
        let reasonText = inference.reasons.isEmpty ? "none" : inference.reasons.joined(separator: "|")
        engineLog(
            "[CTX] context=\(inference.context.rawValue) conf=\(confText) " +
            "frame=\(inference.framingState.rawValue) source=\(inference.source) " +
            "faceRatio=\(ratioText) cam=\(camName) model=\(camModel) reasons=\(reasonText)"
        )
        lastContextInference = inference
        lastContextLogAt = now
    }

    private func setCurrentHeadPoseIfNeeded(pitch: CGFloat, yaw: CGFloat) {
        if abs(currentHeadPitch - pitch) >= 0.25 {
            currentHeadPitch = pitch
        }
        if abs(currentHeadYaw - yaw) >= 0.25 {
            currentHeadYaw = yaw
        }
    }

    private func setDetectionState(bodyDetected detected: Bool, joints: DetectedJoints?) {
        if bodyDetected != detected {
            bodyDetected = detected
        }

        switch (currentJoints, joints) {
        case (nil, nil):
            break
        case (nil, .some), (.some, nil):
            currentJoints = joints
        case let (.some(current), .some(next)):
            if shouldPublishJointsUpdate(from: current, to: next) {
                currentJoints = next
            }
        }
    }

    private func shouldPublishJointsUpdate(from current: DetectedJoints, to next: DetectedJoints) -> Bool {
        let keypointThreshold: CGFloat = 0.000025
        if pointDistanceSquared(current.nose, next.nose) > keypointThreshold { return true }
        if pointDistanceSquared(current.neck, next.neck) > keypointThreshold { return true }
        if pointDistanceSquared(current.leftShoulder, next.leftShoulder) > keypointThreshold { return true }
        if pointDistanceSquared(current.rightShoulder, next.rightShoulder) > keypointThreshold { return true }
        if pointDistanceSquared(current.leftEar, next.leftEar) > keypointThreshold { return true }
        if pointDistanceSquared(current.rightEar, next.rightEar) > keypointThreshold { return true }
        return false
    }

    private func pointDistanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private func setMenuBarIdleIfNeeded(_ isIdle: Bool) {
        if menuBarIsIdle != isIdle {
            menuBarIsIdle = isIdle
        }
    }

    private func inferCameraContext(
        metrics: PostureMetrics,
        baseline: CalibrationData?,
        noseY: CGFloat
    ) -> CameraContextInference {
        var laptopScore: CGFloat = 0
        var desktopScore: CGFloat = 0
        var reasons: [String] = []

        let activeName = (camera.activeDevice?.displayName ?? activeCameraDisplayName).lowercased()
        let activeModel = (camera.activeDevice?.modelID ?? "").lowercased()
        let cameraHintBlob = "\(activeName) \(activeModel)"

        if cameraHintBlob.contains("facetime") || cameraHintBlob.contains("built-in") || cameraHintBlob.contains("macbook") {
            laptopScore += 0.65
            reasons.append("deviceHint:laptop")
        }
        if cameraHintBlob.contains("logi") || cameraHintBlob.contains("logitech") ||
            cameraHintBlob.contains("insta360") || cameraHintBlob.contains("webcam") ||
            cameraHintBlob.contains("external") || cameraHintBlob.contains("display") {
            desktopScore += 0.65
            reasons.append("deviceHint:desktop")
        }
        if cameraSourceMode == .manual {
            desktopScore += 0.20
            reasons.append("manualCameraMode")
        }

        var faceSizeRatio: CGFloat = 0
        if let baseline, baseline.baselineFaceSize > 0.0001 {
            faceSizeRatio = metrics.faceSizeNormalized / baseline.baselineFaceSize
        }

        var framingState: FramingState = .checking
        if faceSizeRatio > 0 {
            if faceSizeRatio > 1.22 {
                framingState = .tooNear
                reasons.append("faceRatio:near")
            } else if faceSizeRatio < 0.82 {
                framingState = .tooFar
                reasons.append("faceRatio:far")
            } else {
                framingState = .stable
            }

            if let baseline,
               framingState == .stable,
               abs(metrics.headPitch - baseline.headPitch) > 8,
               faceSizeRatio < 0.95,
               noseY < 0.40 {
                framingState = .tiltedBack
                reasons.append("tiltBackHeuristic")
            }
        }

        var eyeLevelScore: CGFloat = 0
        if activeModel.contains("macbook") || activeName.contains("facetime") || activeName.contains("built-in") {
            if faceSizeRatio > 0, faceSizeRatio < 0.96, noseY < 0.46 {
                eyeLevelScore += 0.55
                reasons.append("builtInHeuristic:eyeLevel")
            } else {
                laptopScore += 0.15
                reasons.append("builtInHeuristic:belowEye")
            }
        }

        let totalScore = laptopScore + desktopScore + eyeLevelScore
        var context: CameraContext = .unknown
        var confidence: CGFloat = 0
        var source = "auto"

        if totalScore > 0 {
            let ranked: [(CameraContext, CGFloat)] = [
                (.aboveEye, desktopScore),
                (.eyeLevel, eyeLevelScore),
                (.belowEye, laptopScore)
            ].sorted { $0.1 > $1.1 }
            let top = ranked[0]
            let second = ranked.dropFirst().first?.1 ?? 0
            confidence = min(1, (top.1 - second) / max(totalScore, 0.0001))
            if top.1 > 0, confidence >= 0.18 {
                context = top.0
            } else {
                reasons.append("lowConfidence")
            }
        } else {
            reasons.append("noStrongHints")
        }

        if let manualContext = cameraContextSelection.resolvedContext {
            context = manualContext
            confidence = 1
            source = "manual"
            reasons.append("manualContextOverride")
        }

        if framingState == .checking, context != .unknown {
            framingState = .stable
        }

        return CameraContextInference(
            context: context,
            confidence: confidence,
            framingState: framingState,
            source: source,
            faceSizeRatio: faceSizeRatio,
            reasons: reasons
        )
    }

    // MARK: - Power Management

    private func handleNoDetection(at now: Date) {
        guard powerStateManagementEnabled else {
            noDetectionStart = nil
            consecutiveDetections = 0
            if powerState != .active {
                transitionPowerState(to: .active, reason: "power saving disabled")
            }
            return
        }

        consecutiveDetections = 0
        if noDetectionStart == nil {
            noDetectionStart = now
        }
        guard let start = noDetectionStart else { return }

        let elapsed = now.timeIntervalSince(start)
        if elapsed >= inactiveTimeoutInterval {
            transitionPowerState(to: .inactive, reason: "no detection for \(Int(elapsed.rounded()))s")
        } else if elapsed >= drowsyTimeoutInterval {
            transitionPowerState(to: .drowsy, reason: "no detection for \(Int(elapsed.rounded()))s")
        }
    }

    private func handleDetectionSuccess() {
        noDetectionStart = nil

        guard powerStateManagementEnabled else {
            consecutiveDetections = 0
            if powerState != .active {
                transitionPowerState(to: .active, reason: "power saving disabled")
            }
            return
        }

        consecutiveDetections = min(consecutiveDetections + 1, 2)
        guard powerState != .active, consecutiveDetections >= 2 else { return }
        transitionPowerState(to: .active, reason: "reactivated by consecutive detections")
    }

    private func transitionPowerState(to newState: MonitoringPowerState, reason: String? = nil) {
        if !powerStateManagementEnabled && newState != .active {
            return
        }
        guard powerState != newState else { return }

        let previous = powerState
        powerState = newState
        if let reason {
            engineLog("power state \(previous.rawValue) -> \(newState.rawValue) (\(reason))")
        } else {
            engineLog("power state \(previous.rawValue) -> \(newState.rawValue)")
        }

        switch newState {
        case .active:
            stopProbeTimer()
            camera.startSession()
            noDetectionStart = nil
            consecutiveDetections = 0
            scheduleAnalysis(runImmediately: false)
        case .drowsy:
            stopProbeTimer()
            scheduleAnalysis(runImmediately: false)
        case .inactive:
            analysisTimer?.invalidate()
            analysisTimer = nil
            camera.stopSession()
            startProbeTimer()
        }
    }

    private func startProbeTimer() {
        stopProbeTimer()
        guard isMonitoring else { return }

        probeTimer = Timer.scheduledTimer(withTimeInterval: inactiveProbeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runInactiveProbeCycle()
            }
        }
    }

    private func stopProbeTimer() {
        probeTimer?.invalidate()
        probeTimer = nil
        probeTask?.cancel()
        probeTask = nil
    }

    private func runInactiveProbeCycle() {
        guard isMonitoring, powerState == .inactive, powerStateManagementEnabled else { return }
        guard probeTask == nil else { return }

        camera.startSession()
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.probeTask = nil }

            try? await Task.sleep(nanoseconds: UInt64(self.inactiveProbeWarmup * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.isMonitoring, self.powerState == .inactive, self.powerStateManagementEnabled else { return }

            await self.analyzeLatestFrame(isProbe: true)

            if self.powerState == .inactive {
                self.camera.stopSession()
            }
        }
    }

    private func resetPowerManagementState() {
        stopProbeTimer()
        noDetectionStart = nil
        consecutiveDetections = 0
        powerState = .active
    }

    private func handleAutoPauseSettingChanged() {
        noDetectionStart = nil
        consecutiveDetections = 0

        guard isMonitoring else { return }
        if !autoPauseEnabled {
            transitionPowerState(to: .active, reason: "auto-pause disabled")
        } else if powerState == .inactive {
            startProbeTimer()
        } else {
            scheduleAnalysis(runImmediately: false)
        }
    }

    private func handleInactiveTimeoutChanged() {
        let clamped = min(
            max(inactiveTimeout, PowerSavingSettings.minInactiveTimeoutSeconds),
            PowerSavingSettings.maxInactiveTimeoutSeconds
        )
        if clamped != inactiveTimeout {
            inactiveTimeout = clamped
            return
        }
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
        sessionBadPostureSeconds = 0
        sessionResetCount = 0
        sessionLongestSlouchSeconds = 0
        sessionCurrentSlouchStart = nil

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
        sessionBadPostureSeconds = 0
        sessionResetCount = 0
        sessionLongestSlouchSeconds = 0
        sessionCurrentSlouchStart = nil
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
        if shouldCountAsBadPosture {
            if sessionCurrentSlouchStart == nil {
                sessionCurrentSlouchStart = lastTick
            }
            sessionBadPostureSeconds += delta
        }
        sessionLastTick = now
    }

    private var shouldCountAsGoodPosture: Bool {
        calibrationData != nil &&
        !isCalibrating &&
        bodyDetected &&
        postureState.severity == .good
    }

    private var shouldCountAsBadPosture: Bool {
        calibrationData != nil &&
        !isCalibrating &&
        bodyDetected &&
        (postureState.severity == .bad || postureState.severity == .away)
    }

    private func recordSessionSample(score: Int, cva: CGFloat) {
        guard activeSessionID != nil else { return }
        sessionScoreSum += Double(score)
        sessionScoreSampleCount += 1
        sessionCVASum += Double(cva)
        sessionCVASampleCount += 1
    }

    private func trackSlouchTransition(from previous: Severity, to current: Severity, at now: Date) {
        guard activeSessionID != nil else { return }
        guard previous != current else { return }
        let wasBad = isBadSeverity(previous)
        let isBad = isBadSeverity(current)

        if isBad && !wasBad {
            sessionSlouchEventCount += 1
            sessionCurrentSlouchStart = now
        }

        if !isBad && wasBad {
            if let slouchStart = sessionCurrentSlouchStart {
                let slouchDuration = max(0, now.timeIntervalSince(slouchStart))
                sessionLongestSlouchSeconds = max(sessionLongestSlouchSeconds, slouchDuration)
            }
            sessionCurrentSlouchStart = nil
        }

        if isActionableSeverity(previous) && current == .good {
            sessionResetCount += 1
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
        let liveSlouchSeconds: TimeInterval
        if let slouchStart = sessionCurrentSlouchStart, isBadSeverity(postureState.severity) {
            liveSlouchSeconds = max(0, endDate.timeIntervalSince(slouchStart))
        } else {
            liveSlouchSeconds = 0
        }
        let longestSlouchSeconds = max(sessionLongestSlouchSeconds, liveSlouchSeconds)
        let clampedBadSeconds = min(duration, max(0, sessionBadPostureSeconds))

        return SessionRecord(
            id: id,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            averageScore: max(0, min(100, averageScore)),
            goodPosturePercent: max(0, min(100, goodPosturePercent)),
            averageCVA: max(0, averageCVA),
            slouchEventCount: max(0, sessionSlouchEventCount),
            badPostureSeconds: clampedBadSeconds,
            resetCount: max(0, sessionResetCount),
            longestSlouchSeconds: max(0, longestSlouchSeconds)
        )
    }

    private func isBadSeverity(_ severity: Severity) -> Bool {
        severity == .bad || severity == .away
    }

    private func isActionableSeverity(_ severity: Severity) -> Bool {
        severity == .correction || severity == .bad || severity == .away
    }

    // MARK: - Menu Bar Severity Hold Timer

    /// Updates the held menu bar severity with asymmetric and stepped hold times:
    /// - Worsening: first change in ~1.5s, then shorter follow-up steps
    /// - Improving: first change in ~4.0s, then eased follow-up steps
    private func updateMenuBarSeverity(newSeverity: Severity, currentScore: Int, now: Date) {
        menuBarIsIdle = false

        guard newSeverity != menuBarSeverity else {
            // Current severity matches — clear any pending change
            pendingSeverity = nil
            pendingSeverityStart = nil
            pendingTransitionStepCount = 0
            return
        }

        guard shouldStartTransition(from: menuBarSeverity, toward: newSeverity, score: currentScore) else {
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

    private func shouldStartTransition(from current: Severity, toward target: Severity, score: Int) -> Bool {
        guard let threshold = transitionScoreThreshold(from: current, toward: target) else { return true }
        if abs(score - threshold) <= scoreBoundaryBuffer { return false }
        if target > current {
            return score <= threshold - scoreTransitionCrossover  // score dropped below threshold
        }
        return score >= threshold + scoreTransitionCrossover      // score recovered above threshold
    }

    private func transitionScoreThreshold(from current: Severity, toward target: Severity) -> Int? {
        let mode = sensitivityMode
        guard current != target else { return nil }

        if target > current {
            switch current {
            case .good: return mode.goodThreshold
            case .correction: return mode.correctionThreshold
            case .bad: return mode.badThreshold
            case .away: return nil
            }
        }

        switch current {
        case .good: return nil
        case .correction: return mode.goodThreshold
        case .bad: return mode.correctionThreshold
        case .away: return mode.badThreshold
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
            transitionPowerState(to: .active, reason: "calibration started")
            noDetectionStart = nil
            consecutiveDetections = 0
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
