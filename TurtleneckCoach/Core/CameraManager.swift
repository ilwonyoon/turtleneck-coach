import AVFoundation
import AppKit
import CoreImage
import Foundation
import os.log

/// Manages AVCaptureSession for continuous camera feed with periodic frame analysis.
/// Provides frame callbacks for pose detection and display.
final class CameraManager: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.capture", qos: .userInitiated)
    private var isConfigured = false
    private var activeInput: AVCaptureDeviceInput?
    private let ciContext = CIContext()
    private let logger = Logger(subsystem: "com.turtleneck.detector", category: "Camera")
    #if DEBUG
    private struct FramePerfStats {
        var frameCount = 0
        var portraitFrameCount = 0
        var totalConvertMs: Double = 0
        var totalRotateMs: Double = 0
        var totalFrameMs: Double = 0
        var maxConvertMs: Double = 0
        var maxRotateMs: Double = 0
        var maxFrameMs: Double = 0
        var lastReportAt = Date.distantPast
    }
    private var framePerfStats = FramePerfStats()
    private let framePerfReportInterval: TimeInterval = 5.0
    #endif

    /// Called on each new frame with the CGImage (already rotated to landscape if needed).
    var onFrame: ((CGImage) -> Void)?
    /// Called when the camera session is interrupted (e.g. device disconnected).
    var onSessionInterrupted: (() -> Void)?
    /// Called when the camera session resumes after interruption.
    var onSessionResumed: (() -> Void)?
    private(set) var activeDevice: CameraDeviceOption?

    enum CameraError: Error {
        case notAuthorized
        case configurationFailed
    }

    private struct DeviceScore {
        let device: AVCaptureDevice
        let score: Int
    }

    private static func discoveryDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        [.builtInWideAngleCamera, .external]
    }

    private static func discoveredVideoDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: discoveryDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )

        var devices = discovery.devices
        if let fallback = AVCaptureDevice.default(for: .video),
           !devices.contains(where: { $0.uniqueID == fallback.uniqueID }) {
            devices.append(fallback)
        }

        return devices
    }

    private static func isVirtualDevice(_ device: AVCaptureDevice) -> Bool {
        let name = device.localizedName.lowercased()
        let model = device.modelID.lowercased()
        return name.contains("virtual") || model.contains("virtual")
    }

    private static func scoreForAutoSelection(_ device: AVCaptureDevice) -> Int {
        let name = device.localizedName.lowercased()
        let isFaceTime = name.contains("facetime")
        let isBuiltIn = device.deviceType == .builtInWideAngleCamera
        let isVirtual = isVirtualDevice(device)

        var score = 0
        if isFaceTime { score += 100 }
        if isBuiltIn { score += 50 }
        // De-prioritize virtual devices in auto mode, but do not exclude them.
        if isVirtual { score -= 1_000 }
        return score
    }

    private static func orderedVideoDevicesForAutoSelection() -> [DeviceScore] {
        discoveredVideoDevices()
            .map { DeviceScore(device: $0, score: scoreForAutoSelection($0)) }
            .sorted { $0.score > $1.score }
    }

    private static func makeDeviceOption(from device: AVCaptureDevice) -> CameraDeviceOption {
        CameraDeviceOption(
            uniqueID: device.uniqueID,
            displayName: device.localizedName,
            modelID: device.modelID,
            isVirtual: isVirtualDevice(device)
        )
    }

    static func discoverVideoDevices() -> [CameraDeviceOption] {
        orderedVideoDevicesForAutoSelection().map { makeDeviceOption(from: $0.device) }
    }

    /// Prefer user-selected camera first. Without a user preference, favor physical cameras.
    private func selectPreferredVideoDevice() -> AVCaptureDevice? {
        let scoredDevices = Self.orderedVideoDevicesForAutoSelection()
        guard !scoredDevices.isEmpty else {
            return AVCaptureDevice.default(for: .video)
        }

        if #available(macOS 14.0, *) {
            if let preferred = AVCaptureDevice.userPreferredCamera,
               scoredDevices.contains(where: { $0.device.uniqueID == preferred.uniqueID }) {
                logger.log(
                    "Selected user preferred camera: \(preferred.localizedName, privacy: .public) (model: \(preferred.modelID, privacy: .public))"
                )
                return preferred
            }
        }

        if let first = scoredDevices.first {
            logger.log(
                "Selected auto camera: \(first.device.localizedName, privacy: .public) (model: \(first.device.modelID, privacy: .public), score: \(first.score, privacy: .public))"
            )
            return first.device
        }

        return AVCaptureDevice.default(for: .video)
    }

    private func selectDevice(sourceMode: CameraSourceMode, manualDeviceID: String?) -> AVCaptureDevice? {
        if sourceMode == .manual,
           let manualDeviceID,
           !manualDeviceID.isEmpty {
            if let manualDevice = Self.discoveredVideoDevices().first(where: { $0.uniqueID == manualDeviceID }) {
                logger.log(
                    "Selected manual camera: \(manualDevice.localizedName, privacy: .public) (model: \(manualDevice.modelID, privacy: .public))"
                )
                return manualDevice
            }
            logger.log("Manual camera id \(manualDeviceID, privacy: .public) not found. Falling back to auto selection.")
        }

        return selectPreferredVideoDevice()
    }

    private func switchInputIfNeeded(to device: AVCaptureDevice) throws {
        if activeInput?.device.uniqueID == device.uniqueID {
            activeDevice = Self.makeDeviceOption(from: device)
            return
        }

        let newInput = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        let previousInput = activeInput
        if let previousInput {
            session.removeInput(previousInput)
        }

        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
            }
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }

        session.addInput(newInput)
        session.commitConfiguration()
        activeInput = newInput
        activeDevice = Self.makeDeviceOption(from: device)
    }

    private func configure(for device: AVCaptureDevice) throws {
        if isConfigured {
            try switchInputIfNeeded(to: device)
            return
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .medium

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        activeInput = input
        activeDevice = Self.makeDeviceOption(from: device)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addOutput(output)

        // Do NOT set videoOrientation - we rotate in software for compatibility
        // with cameras like Insta360 Link 2 that output portrait frames.

        session.commitConfiguration()
        isConfigured = true
        registerSessionNotifications()
    }

    private var interruptionObserver: NSObjectProtocol?
    private var resumeObserver: NSObjectProtocol?

    private func registerSessionNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.logger.log("Camera session interrupted")
            self?.onSessionInterrupted?()
        }
        resumeObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.logger.log("Camera session interruption ended")
            self?.onSessionResumed?()
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let resumeObserver {
            NotificationCenter.default.removeObserver(resumeObserver)
        }
        session.stopRunning()
    }

    /// Request camera permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Configure the capture session using auto selection.
    func configure() throws {
        guard let device = selectPreferredVideoDevice() else {
            throw CameraError.configurationFailed
        }
        try configure(for: device)
    }

    /// Start the continuous camera session with source policy.
    func start(sourceMode: CameraSourceMode, manualDeviceID: String?) async throws {
        guard await CameraManager.requestPermission() else {
            throw CameraError.notAuthorized
        }

        guard let device = selectDevice(sourceMode: sourceMode, manualDeviceID: manualDeviceID) else {
            throw CameraError.configurationFailed
        }

        try configure(for: device)
        startSession()
    }

    /// Start the continuous camera session (backwards compatible).
    func start() async throws {
        try await start(sourceMode: .auto, manualDeviceID: nil)
    }

    /// Stop the camera session.
    func stop() {
        stopSession()
    }

    /// Start or resume AVCaptureSession safely (idempotent).
    func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isConfigured else { return }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    /// Stop AVCaptureSession safely (idempotent).
    func stopSession() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Rotate a portrait CGImage 90° counter-clockwise to landscape using CIImage transforms.
    private func rotateToLandscape(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        // .left orientation = 90° counter-clockwise rotation
        let oriented = ciImage.oriented(.left)
        let extent = oriented.extent
        return ciContext.createCGImage(oriented, from: extent)
    }

    #if DEBUG
    private func recordFramePerf(
        isPortrait: Bool,
        convertMs: Double,
        rotateMs: Double,
        totalFrameMs: Double
    ) {
        framePerfStats.frameCount += 1
        if isPortrait {
            framePerfStats.portraitFrameCount += 1
        }
        framePerfStats.totalConvertMs += convertMs
        framePerfStats.totalRotateMs += rotateMs
        framePerfStats.totalFrameMs += totalFrameMs
        framePerfStats.maxConvertMs = max(framePerfStats.maxConvertMs, convertMs)
        framePerfStats.maxRotateMs = max(framePerfStats.maxRotateMs, rotateMs)
        framePerfStats.maxFrameMs = max(framePerfStats.maxFrameMs, totalFrameMs)

        let now = Date()
        guard now.timeIntervalSince(framePerfStats.lastReportAt) >= framePerfReportInterval else { return }
        guard framePerfStats.frameCount > 0 else { return }

        let frames = Double(framePerfStats.frameCount)
        let avgConvert = framePerfStats.totalConvertMs / frames
        let avgRotate = framePerfStats.totalRotateMs / frames
        let avgFrame = framePerfStats.totalFrameMs / frames
        DebugLogWriter.append(String(
            format: "%@: [PERF_CAMERA] frames=%d portrait=%d avgConvertMs=%.2f avgRotateMs=%.2f avgFrameMs=%.2f maxConvertMs=%.2f maxRotateMs=%.2f maxFrameMs=%.2f\n",
            ISO8601DateFormatter().string(from: now),
            framePerfStats.frameCount,
            framePerfStats.portraitFrameCount,
            avgConvert,
            avgRotate,
            avgFrame,
            framePerfStats.maxConvertMs,
            framePerfStats.maxRotateMs,
            framePerfStats.maxFrameMs
        ))
        framePerfStats = FramePerfStats(lastReportAt: now)
    }
    #endif
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let onFrame else { return }
        #if DEBUG
        let frameStart = CFAbsoluteTimeGetCurrent()
        #endif

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0, y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        #if DEBUG
        let convertStart = CFAbsoluteTimeGetCurrent()
        #endif
        guard let rawImage = ciContext.createCGImage(ciImage, from: rect) else { return }
        #if DEBUG
        let convertMs = (CFAbsoluteTimeGetCurrent() - convertStart) * 1000
        #endif

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let isPortrait = h > w

        // If portrait, rotate to landscape
        let finalImage: CGImage
        #if DEBUG
        let rotateStart = CFAbsoluteTimeGetCurrent()
        #endif
        if isPortrait {
            guard let rotated = rotateToLandscape(rawImage) else { return }
            finalImage = rotated
        } else {
            finalImage = rawImage
        }
        #if DEBUG
        let rotateMs = isPortrait ? (CFAbsoluteTimeGetCurrent() - rotateStart) * 1000 : 0
        let totalFrameMs = (CFAbsoluteTimeGetCurrent() - frameStart) * 1000
        recordFramePerf(
            isPortrait: isPortrait,
            convertMs: convertMs,
            rotateMs: rotateMs,
            totalFrameMs: totalFrameMs
        )
        #endif

        #if DEBUG
        if Int.random(in: 0..<90) == 0 {
            print("[Camera] Frame: \(w)x\(h) → \(finalImage.width)x\(finalImage.height)")
        }
        #endif
        onFrame(finalImage)
    }
}
