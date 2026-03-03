// Standalone test: capture one frame, check dimensions, run Vision, save result
import AVFoundation
import Vision
import CoreImage
import AppKit

class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let output = AVCaptureVideoDataOutput()
    let queue = DispatchQueue(label: "test.camera")
    let ciContext = CIContext()
    var frameCount = 0
    var gotFrame = false

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            print("ERROR: No camera device found")
            exit(1)
        }
        print("Camera: \(device.localizedName)")
        print("Model ID: \(device.modelID)")

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)

        // Log connection info
        if let conn = output.connection(with: .video) {
            print("Connection videoOrientation: \(conn.videoOrientation.rawValue)")
            print("  isVideoOrientationSupported: \(conn.isVideoOrientationSupported)")
            print("  isVideoMirroringSupported: \(conn.isVideoMirroringSupported)")
            print("  isVideoMirrored: \(conn.isVideoMirrored)")

            // Try NOT setting orientation at all first
            print("  NOT changing orientation - using camera default")
        }

        session.commitConfiguration()
        session.startRunning()
        print("Session started, waiting for frames...")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard !gotFrame, frameCount > 5 else { return }  // Skip first few frames
        gotFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("ERROR: No pixel buffer")
            return
        }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        print("\nFrame #\(frameCount): \(w)x\(h) (portrait=\(h > w))")

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            print("ERROR: Can't create CGImage")
            return
        }

        // Save raw frame as PNG for inspection
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: "/tmp/turtle_test_frame.png")
            try? pngData.write(to: url)
            print("Saved raw frame to /tmp/turtle_test_frame.png")
        }

        // Run Vision body pose detection
        print("\nRunning Vision body pose detection...")
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            if let results = request.results, !results.isEmpty {
                print("BODY DETECTED! \(results.count) observation(s)")
                let obs = results[0]

                // Try to get all our target joints
                let jointNames: [(VNHumanBodyPoseObservation.JointName, String)] = [
                    (.nose, "nose"), (.neck, "neck"),
                    (.leftEar, "leftEar"), (.rightEar, "rightEar"),
                    (.leftEye, "leftEye"), (.rightEye, "rightEye"),
                    (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
                ]

                for (jointName, label) in jointNames {
                    if let point = try? obs.recognizedPoint(jointName) {
                        print("  \(label): (\(String(format: "%.3f", point.location.x)), \(String(format: "%.3f", point.location.y))) conf=\(String(format: "%.2f", point.confidence))")
                    } else {
                        print("  \(label): NOT FOUND")
                    }
                }
            } else {
                print("NO BODY DETECTED in frame")
            }
        } catch {
            print("Vision error: \(error)")
        }

        // Stop after getting result
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.session.stopRunning()
            print("\nTest complete.")
            exit(0)
        }
    }
}

// Main
print("=== Camera + Vision Test ===")
let grabber = FrameGrabber()
do {
    try grabber.start()
} catch {
    print("Failed to start: \(error)")
    exit(1)
}

// Run loop to keep alive
RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
print("Timeout - no frames received")
exit(1)
