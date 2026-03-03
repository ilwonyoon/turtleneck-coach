// Test: capture frame, rotate if portrait, run Vision on rotated frame
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

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .medium
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        print("Waiting for frames...")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard !gotFrame, frameCount > 5 else { return }
        gotFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        print("Raw frame: \(w)x\(h)")

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let rawImage = ciContext.createCGImage(ciImage, from: rect) else { return }

        // Rotate if portrait
        let finalImage: CGImage
        if h > w {
            print("Portrait detected → rotating 90° clockwise")
            let oriented = CIImage(cgImage: rawImage).oriented(.left)
            guard let rotated = ciContext.createCGImage(oriented, from: oriented.extent) else {
                print("ERROR: rotation failed")
                return
            }
            finalImage = rotated
            print("Rotated frame: \(finalImage.width)x\(finalImage.height)")
        } else {
            finalImage = rawImage
        }

        // Save rotated frame
        let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: "/tmp/turtle_rotated.png"))
            print("Saved rotated frame to /tmp/turtle_rotated.png")
        }

        // Run Vision on rotated frame
        print("\nRunning Vision on rotated frame...")
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: finalImage, options: [:])
        do {
            try handler.perform([request])
            if let results = request.results, !results.isEmpty {
                print("✓ BODY DETECTED!")
                let obs = results[0]
                let joints: [(VNHumanBodyPoseObservation.JointName, String)] = [
                    (.nose, "nose"), (.neck, "neck"),
                    (.leftEar, "leftEar"), (.rightEar, "rightEar"),
                    (.leftEye, "leftEye"), (.rightEye, "rightEye"),
                    (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
                ]
                for (jn, label) in joints {
                    if let pt = try? obs.recognizedPoint(jn) {
                        print("  \(label): (\(String(format: "%.3f", pt.location.x)), \(String(format: "%.3f", pt.location.y))) conf=\(String(format: "%.2f", pt.confidence))")
                    } else {
                        print("  \(label): NOT FOUND")
                    }
                }
            } else {
                print("✗ NO BODY DETECTED")
            }
        } catch {
            print("Vision error: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.session.stopRunning()
            exit(0)
        }
    }
}

print("=== Rotation + Vision Test ===")
let grabber = FrameGrabber()
do { try grabber.start() } catch { print("Failed: \(error)"); exit(1) }
RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
exit(1)
