import AVFoundation
import AppKit
import CoreImage

/// Manages AVCaptureSession for continuous camera feed with periodic frame analysis.
/// Provides frame callbacks for pose detection and display.
final class CameraManager: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.capture", qos: .userInitiated)
    private var isConfigured = false
    private let ciContext = CIContext()

    /// Called on each new frame with the CGImage (already rotated to landscape if needed).
    var onFrame: ((CGImage) -> Void)?

    enum CameraError: Error {
        case notAuthorized
        case configurationFailed
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

    /// Configure the capture session (called once).
    func configure() throws {
        guard !isConfigured else { return }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.configurationFailed
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .medium

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addInput(input)

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
    }

    /// Start the continuous camera session.
    func start() async throws {
        guard await CameraManager.requestPermission() else {
            throw CameraError.notAuthorized
        }
        try configure()
        startSession()
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
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let onFrame else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0, y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        guard let rawImage = ciContext.createCGImage(ciImage, from: rect) else { return }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let isPortrait = h > w

        // If portrait, rotate to landscape
        let finalImage: CGImage
        if isPortrait {
            guard let rotated = rotateToLandscape(rawImage) else { return }
            finalImage = rotated
        } else {
            finalImage = rawImage
        }

        #if DEBUG
        if Int.random(in: 0..<90) == 0 {
            print("[Camera] Frame: \(w)x\(h) → \(finalImage.width)x\(finalImage.height)")
        }
        #endif
        onFrame(finalImage)
    }
}
