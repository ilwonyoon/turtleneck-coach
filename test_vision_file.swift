// Test Vision body pose detection on the captured frame
// Also test if the issue is contrast/clothing by trying different approaches
import Vision
import CoreImage
import AppKit
import Foundation

func testBodyPose(image: CGImage, label: String) {
    print("\n--- \(label) (\(image.width)x\(image.height)) ---")

    let bodyReq = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
        try handler.perform([bodyReq])
        if let results = bodyReq.results, !results.isEmpty {
            print("  ✓ BODY DETECTED (\(results.count) observation)")
            let obs = results[0]
            let allJoints = try obs.recognizedPoints(.all)
            print("  Total joints found: \(allJoints.count)")
            for (key, point) in allJoints.sorted(by: { $0.key.rawValue.rawValue < $1.key.rawValue.rawValue }) {
                if point.confidence > 0.01 {
                    print("    \(key.rawValue.rawValue): (\(String(format: "%.3f", point.location.x)), \(String(format: "%.3f", point.location.y))) conf=\(String(format: "%.3f", point.confidence))")
                }
            }
        } else {
            print("  ✗ NO BODY DETECTED")
        }
    } catch {
        print("  Error: \(error)")
    }
}

// Test 1: Load captured frame
print("=== Vision Body Pose File Test ===")

let paths = ["/tmp/turtle_frame3.png", "/tmp/turtle_rotated.png", "/tmp/turtle_high.png"]

for path in paths {
    let url = URL(fileURLWithPath: path)
    guard let nsImage = NSImage(contentsOf: url) else {
        print("Cannot load \(path)")
        continue
    }
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Cannot get CGImage from \(path)")
        continue
    }
    testBodyPose(image: cgImage, label: path)
}

// Test 2: Try with brightness/contrast adjusted version
if let nsImage = NSImage(contentsOf: URL(fileURLWithPath: "/tmp/turtle_frame3.png")),
   let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {

    // Brighten the image
    let ciImage = CIImage(cgImage: cgImage)
    let brightened = ciImage.applyingFilter("CIColorControls", parameters: [
        kCIInputBrightnessKey: 0.3,
        kCIInputContrastKey: 1.3
    ])
    let ctx = CIContext()
    if let brightCG = ctx.createCGImage(brightened, from: brightened.extent) {
        testBodyPose(image: brightCG, label: "Brightened frame")

        // Save for visual check
        let rep = NSBitmapImageRep(cgImage: brightCG)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/turtle_bright.png"))
            print("  Saved brightened to /tmp/turtle_bright.png")
        }
    }
}

print("\nDone.")
