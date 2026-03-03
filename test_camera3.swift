// Test: try different presets and also test face detection
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
            print("ERROR: No camera device found"); exit(1)
        }
        print("Camera: \(device.localizedName)")

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        // Try high preset for better resolution
        session.sessionPreset = .high
        print("Using preset: high")
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
        guard !gotFrame, frameCount > 10 else { return }  // Wait a bit longer for exposure
        gotFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        print("Raw frame: \(w)x\(h)")

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let rawImage = ciContext.createCGImage(ciImage, from: rect) else { return }

        let finalImage: CGImage
        if h > w {
            let oriented = CIImage(cgImage: rawImage).oriented(.left)
            guard let rotated = ciContext.createCGImage(oriented, from: oriented.extent) else { return }
            finalImage = rotated
            print("Rotated: \(finalImage.width)x\(finalImage.height)")
        } else {
            finalImage = rawImage
        }

        // Save frame
        let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: "/tmp/turtle_high.png"))
            print("Saved to /tmp/turtle_high.png")
        }

        // Test 1: Body pose detection
        print("\n--- Body Pose Detection ---")
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let handler1 = VNImageRequestHandler(cgImage: finalImage, options: [:])
        do {
            try handler1.perform([bodyRequest])
            if let results = bodyRequest.results, !results.isEmpty {
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
                    }
                }
            } else {
                print("✗ NO BODY DETECTED")
            }
        } catch {
            print("Error: \(error)")
        }

        // Test 2: Face detection (as sanity check)
        print("\n--- Face Detection ---")
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler2 = VNImageRequestHandler(cgImage: finalImage, options: [:])
        do {
            try handler2.perform([faceRequest])
            if let faces = faceRequest.results, !faces.isEmpty {
                print("✓ FACE DETECTED! (\(faces.count) face(s))")
                for (i, face) in faces.enumerated() {
                    print("  Face \(i): bounds=\(face.boundingBox) conf=\(String(format: "%.2f", face.confidence))")
                }
            } else {
                print("✗ NO FACE DETECTED")
            }
        } catch {
            print("Error: \(error)")
        }

        // Test 3: Body pose with orientation hint on raw (un-rotated) image
        if h > w {
            print("\n--- Body Pose (orientation hint on raw) ---")
            let bodyRequest2 = VNDetectHumanBodyPoseRequest()
            let handler3 = VNImageRequestHandler(cgImage: rawImage, orientation: .left, options: [:])
            do {
                try handler3.perform([bodyRequest2])
                if let results = bodyRequest2.results, !results.isEmpty {
                    print("✓ BODY DETECTED with orientation hint!")
                    let obs = results[0]
                    let joints: [(VNHumanBodyPoseObservation.JointName, String)] = [
                        (.nose, "nose"), (.neck, "neck"),
                        (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
                    ]
                    for (jn, label) in joints {
                        if let pt = try? obs.recognizedPoint(jn) {
                            print("  \(label): (\(String(format: "%.3f", pt.location.x)), \(String(format: "%.3f", pt.location.y))) conf=\(String(format: "%.2f", pt.confidence))")
                        }
                    }
                } else {
                    print("✗ NO BODY with orientation hint either")
                }
            } catch {
                print("Error: \(error)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.session.stopRunning()
            print("\nDone.")
            exit(0)
        }
    }
}

let grabber = FrameGrabber()
do { try grabber.start() } catch { print("Failed: \(error)"); exit(1) }
RunLoop.main.run(until: Date(timeIntervalSinceNow: 20))
exit(1)
