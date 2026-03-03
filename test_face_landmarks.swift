// Test: use face landmarks to estimate head position/tilt as posture proxy
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
        guard let device = AVCaptureDevice.default(for: .video) else { exit(1) }
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
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard !gotFrame, frameCount > 15 else { return }
        gotFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let rawImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return }

        let finalImage: CGImage
        if h > w {
            let oriented = CIImage(cgImage: rawImage).oriented(.left)
            guard let rotated = ciContext.createCGImage(oriented, from: oriented.extent) else { return }
            finalImage = rotated
        } else {
            finalImage = rawImage
        }
        print("Frame: \(finalImage.width)x\(finalImage.height)")

        // Try face landmarks
        let faceLandmarksReq = VNDetectFaceLandmarksRequest()
        let faceRectReq = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: finalImage, options: [:])
        do {
            try handler.perform([faceRectReq, faceLandmarksReq])

            if let faces = faceLandmarksReq.results, !faces.isEmpty {
                let face = faces[0]
                let bbox = face.boundingBox
                print("\n✓ Face detected!")
                print("  BBox: x=\(String(format: "%.3f", bbox.origin.x)) y=\(String(format: "%.3f", bbox.origin.y)) w=\(String(format: "%.3f", bbox.width)) h=\(String(format: "%.3f", bbox.height))")
                print("  Roll: \(face.roll?.floatValue ?? 0)°")
                print("  Yaw: \(face.yaw?.floatValue ?? 0)°")
                print("  Pitch: \(face.pitch?.floatValue ?? 0)°")

                if let landmarks = face.landmarks {
                    if let nose = landmarks.noseCrest {
                        let pts = nose.normalizedPoints
                        print("  Nose crest points: \(pts.count)")
                        if let tip = pts.last {
                            // Convert to image coordinates
                            let imgX = bbox.origin.x + tip.x * bbox.width
                            let imgY = bbox.origin.y + tip.y * bbox.height
                            print("  Nose tip (norm): (\(String(format: "%.3f", imgX)), \(String(format: "%.3f", imgY)))")
                        }
                    }
                    if let leftEye = landmarks.leftEye {
                        let pts = leftEye.normalizedPoints
                        let center = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                        let cx = bbox.origin.x + (center.x / CGFloat(pts.count)) * bbox.width
                        let cy = bbox.origin.y + (center.y / CGFloat(pts.count)) * bbox.height
                        print("  Left eye center (norm): (\(String(format: "%.3f", cx)), \(String(format: "%.3f", cy)))")
                    }
                    if let rightEye = landmarks.rightEye {
                        let pts = rightEye.normalizedPoints
                        let center = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                        let cx = bbox.origin.x + (center.x / CGFloat(pts.count)) * bbox.width
                        let cy = bbox.origin.y + (center.y / CGFloat(pts.count)) * bbox.height
                        print("  Right eye center (norm): (\(String(format: "%.3f", cx)), \(String(format: "%.3f", cy)))")
                    }
                    if let faceContour = landmarks.faceContour {
                        let pts = faceContour.normalizedPoints
                        print("  Face contour points: \(pts.count)")
                        // Chin = middle point of contour (bottom of face)
                        let chin = pts[pts.count / 2]
                        let chinX = bbox.origin.x + chin.x * bbox.width
                        let chinY = bbox.origin.y + chin.y * bbox.height
                        print("  Chin (norm): (\(String(format: "%.3f", chinX)), \(String(format: "%.3f", chinY)))")
                    }

                    // Face vertical position in frame as posture indicator
                    // Higher face = more upright; lower face = slouching
                    let faceCenterY = bbox.origin.y + bbox.height / 2
                    print("\n  Face center Y: \(String(format: "%.3f", faceCenterY)) (0=bottom, 1=top)")
                    print("  Face bbox top: \(String(format: "%.3f", bbox.origin.y + bbox.height))")
                    print("  Face bbox bottom: \(String(format: "%.3f", bbox.origin.y))")
                }
            } else {
                print("✗ No face landmarks")
            }
        } catch {
            print("Error: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.session.stopRunning()
            exit(0)
        }
    }
}

print("=== Face Landmarks Test ===")
let grabber = FrameGrabber()
do { try grabber.start() } catch { exit(1) }
RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
exit(1)
