// Test if VNDetectHumanBodyPose3DRequest works on this system
import Vision
import AppKit
import Foundation

print("=== 3D Body Pose Test ===")
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

// Check availability
if #available(macOS 14.0, *) {
    print("VNDetectHumanBodyPose3DRequest: AVAILABLE")

    // Try with a saved frame if available
    let paths = ["/tmp/turtle_frame3.png", "/tmp/turtle_rotated.png"]
    for path in paths {
        let url = URL(fileURLWithPath: path)
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Cannot load \(path)")
            continue
        }

        print("\n--- 3D Pose: \(path) (\(cgImage.width)x\(cgImage.height)) ---")

        let req3D = VNDetectHumanBodyPose3DRequest()
        let req2D = VNDetectHumanBodyPoseRequest()
        let faceReq = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([req3D, req2D, faceReq])

            // 3D results
            if let results3D = req3D.results, !results3D.isEmpty {
                print("  3D BODY DETECTED (\(results3D.count) observation)")
                let obs = results3D[0]

                // Try to get key joints
                let jointNames: [VNHumanBodyPose3DObservation.JointName] = [
                    .centerHead, .topHead,
                    .leftShoulder, .rightShoulder,
                    .spine,
                    .root
                ]

                for name in jointNames {
                    if let point = try? obs.recognizedPoint(name) {
                        let pos = point.position  // simd_float4x4
                        print("    \(name.rawValue): position=(\(pos.columns.3.x), \(pos.columns.3.y), \(pos.columns.3.z))")
                    }
                }

                // Check available joints
                print("  Available joint names:")
                if let allJoints = try? obs.recognizedPoints(.all) {
                    for (key, _) in allJoints {
                        print("    - \(key.rawValue)")
                    }
                }
            } else {
                print("  3D: NO BODY DETECTED")
            }

            // 2D results
            if let results2D = req2D.results, !results2D.isEmpty {
                print("  2D BODY DETECTED")
            } else {
                print("  2D: NO BODY DETECTED")
            }

            // Face results
            if let faceResults = faceReq.results, !faceResults.isEmpty {
                let face = faceResults[0]
                print("  FACE DETECTED: bbox=\(face.boundingBox)")
                if let pitch = face.pitch { print("    pitch=\(pitch)") }
                if let yaw = face.yaw { print("    yaw=\(yaw)") }
                if let roll = face.roll { print("    roll=\(roll)") }
                if let quality = face.faceCaptureQuality { print("    quality=\(quality)") }
            } else {
                print("  FACE: NOT DETECTED")
            }

        } catch {
            print("  Error: \(error)")
        }
    }
} else {
    print("VNDetectHumanBodyPose3DRequest: NOT AVAILABLE (need macOS 14+)")
}

print("\nDone.")
