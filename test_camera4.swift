// Test: grab 5 frames over 3 seconds, rotate, save all, test vision on each
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
    var savedCount = 0
    let maxFrames = 5
    var lastSave: Date = .distantPast

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            print("ERROR: No camera"); exit(1)
        }
        print("Camera: \(device.localizedName)")

        // List all formats to find the best one
        let formats = device.formats
        print("Available format count: \(formats.count)")

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
        print("Running... will grab \(maxFrames) frames over time")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1

        // Skip early frames (exposure settling) and space out saves
        guard frameCount > 15 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSave) >= 0.5 else { return }
        guard savedCount < maxFrames else { return }

        lastSave = now
        savedCount += 1

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let rawImage = ciContext.createCGImage(ciImage, from: rect) else { return }

        let finalImage: CGImage
        if h > w {
            let oriented = CIImage(cgImage: rawImage).oriented(.left)
            guard let rotated = ciContext.createCGImage(oriented, from: oriented.extent) else { return }
            finalImage = rotated
        } else {
            finalImage = rawImage
        }

        print("\nFrame \(savedCount)/\(maxFrames): \(finalImage.width)x\(finalImage.height)")

        // Save
        let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: "/tmp/turtle_frame\(savedCount).png"))
        }

        // Body pose
        let bodyReq = VNDetectHumanBodyPoseRequest()
        do {
            let handler = VNImageRequestHandler(cgImage: finalImage, options: [:])
            try handler.perform([bodyReq])
            if let results = bodyReq.results, !results.isEmpty {
                print("  ✓ BODY DETECTED")
                let obs = results[0]
                for jn in [VNHumanBodyPoseObservation.JointName.nose, .neck, .leftShoulder, .rightShoulder, .leftEar, .rightEar] {
                    if let pt = try? obs.recognizedPoint(jn) {
                        print("    \(jn.rawValue.rawValue): conf=\(String(format: "%.2f", pt.confidence))")
                    }
                }
            } else {
                print("  ✗ No body")
            }
        } catch {
            print("  Error: \(error)")
        }

        // Also try with upscaled image (in case resolution is too low)
        if savedCount == 1 {
            print("\n  Trying with .high preset next time...")
        }

        if savedCount >= maxFrames {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.session.stopRunning()
                print("\nAll frames captured. Check /tmp/turtle_frame*.png")
                exit(0)
            }
        }
    }
}

let grabber = FrameGrabber()
do { try grabber.start() } catch { print("Failed: \(error)"); exit(1) }
RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
exit(1)
