import Vision
import CoreGraphics
import Foundation

/// Joint positions extracted from pose or face detection.
/// All coordinates normalized (0-1), converted to top-left origin.
struct DetectedJoints {
    let nose: CGPoint
    let neck: CGPoint
    let leftEar: CGPoint
    let rightEar: CGPoint
    let leftEye: CGPoint
    let rightEye: CGPoint
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint

    let leftEarConfidence: Float
    let rightEarConfidence: Float

    var allPoints: [(name: String, point: CGPoint)] {
        [
            ("nose", nose), ("neck", neck),
            ("leftEar", leftEar), ("rightEar", rightEar),
            ("leftEye", leftEye), ("rightEye", rightEye),
            ("leftShoulder", leftShoulder), ("rightShoulder", rightShoulder),
        ]
    }

    static let connections: [(String, String)] = [
        ("leftEar", "leftEye"),
        ("rightEar", "rightEye"),
        ("leftEye", "nose"),
        ("rightEye", "nose"),
        ("nose", "neck"),
        ("neck", "leftShoulder"),
        ("neck", "rightShoulder"),
        ("leftShoulder", "rightShoulder"),
    ]
}

struct DetectionResult {
    let metrics: PostureMetrics
    let joints: DetectedJoints
}

/// Wraps Apple Vision for pose detection with face landmarks fallback.
final class VisionPoseDetector {

    private static let earVisibilityThreshold: Float = 0.5

    init() {
        // Write startup marker to confirm logging works
        let msg = "VisionPoseDetector init at \(Date())\n"
        let url = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
        try? msg.data(using: .utf8)?.write(to: url)
    }

    // Face baseline stored during calibration
    private var calibratedFaceY: CGFloat?       // face center Y in normalized Vision coords
    private var calibratedFaceHeight: CGFloat?  // face bbox height (normalized)
    private var calibratedPitch: CGFloat?       // head pitch at calibration

    // Smoothing: keep last few face readings for stability
    private var recentFaceY: [CGFloat] = []
    private var recentFaceHeight: [CGFloat] = []
    private var recentPitch: [CGFloat] = []
    private let smoothingWindow = 5
    private var debugCounter = 0
    private func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Detect pose in image. Tries 2D body pose first, then face landmarks fallback.
    func detect(in image: CGImage) throws -> DetectionResult? {
        if debugCounter == 0 { log("[INIT] detect() called, image=\(image.width)x\(image.height)") }

        let body2DReq = VNDetectHumanBodyPoseRequest()
        let faceReq = VNDetectFaceLandmarksRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([body2DReq, faceReq])

        // Priority 1: 2D body pose (stable neckEarAngle from ear-neck geometry)
        let bodyResults = body2DReq.results ?? []
        if debugCounter % 10 == 0 { log("[BODY] results=\(bodyResults.count)") }
        if let bodyObs = bodyResults.first,
           let bodyResult = try? extractBodyResult(from: bodyObs, imageWidth: image.width, imageHeight: image.height) {
            if debugCounter % 10 == 0 { log("[PATH] 2D body pose → CVA=\(String(format: "%.1f", bodyResult.metrics.neckEarAngle))") }
            debugCounter += 1
            // Clear face smoothing buffers so stale face data doesn't pollute
            // the next face fallback transition
            recentFaceY.removeAll()
            recentFaceHeight.removeAll()
            recentPitch.removeAll()
            return bodyResult
        }

        // Priority 2: Face landmarks fallback
        if let faceObs = faceReq.results?.first {
            if let quality = faceObs.faceCaptureQuality, quality < 0.3 {
                if debugCounter % 10 == 0 { log("[PATH] Face rejected (quality=\(String(format: "%.2f", quality)))") }
                debugCounter += 1
                return nil
            }
            let result = extractFaceResult(from: faceObs, imageWidth: image.width, imageHeight: image.height)
            debugCounter += 1
            return result
        }

        return nil
    }

    /// Store current face metrics as calibration baseline.
    func calibrateFaceBaseline() {
        if !recentFaceY.isEmpty {
            calibratedFaceY = recentFaceY.reduce(0, +) / CGFloat(recentFaceY.count)
            calibratedFaceHeight = recentFaceHeight.reduce(0, +) / CGFloat(recentFaceHeight.count)
            calibratedPitch = recentPitch.reduce(0, +) / CGFloat(recentPitch.count)
        }
    }

    /// Clear face calibration baseline (called when user resets calibration).
    func resetFaceBaseline() {
        calibratedFaceY = nil
        calibratedFaceHeight = nil
        calibratedPitch = nil
        recentFaceY.removeAll()
        recentFaceHeight.removeAll()
        recentPitch.removeAll()
    }

    // MARK: - 2D Body Pose Detection

    private func extractBodyResult(
        from observation: VNHumanBodyPoseObservation,
        imageWidth: Int, imageHeight: Int
    ) throws -> DetectionResult? {
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)

        guard let noseP = try? observation.recognizedPoint(.nose),
              let neckP = try? observation.recognizedPoint(.neck),
              let lEarP = try? observation.recognizedPoint(.leftEar),
              let rEarP = try? observation.recognizedPoint(.rightEar),
              let lEyeP = try? observation.recognizedPoint(.leftEye),
              let rEyeP = try? observation.recognizedPoint(.rightEye),
              let lShP = try? observation.recognizedPoint(.leftShoulder),
              let rShP = try? observation.recognizedPoint(.rightShoulder)
        else {
            if debugCounter % 10 == 0 { log("[BODY] extractBodyResult: missing joints") }
            return nil
        }

        guard neckP.confidence > 0.1, lShP.confidence > 0.1, rShP.confidence > 0.1 else {
            if debugCounter % 10 == 0 {
                log(String(format: "[BODY] low confidence: neck=%.2f lSh=%.2f rSh=%.2f",
                    neckP.confidence, lShP.confidence, rShP.confidence))
            }
            return nil
        }

        let earsVisible = lEarP.confidence > Self.earVisibilityThreshold
            && rEarP.confidence > Self.earVisibilityThreshold

        // Pixel coords (top-left origin)
        let nose = CGPoint(x: noseP.location.x * w, y: (1 - noseP.location.y) * h)
        let neck = CGPoint(x: neckP.location.x * w, y: (1 - neckP.location.y) * h)
        let lEar = CGPoint(x: lEarP.location.x * w, y: (1 - lEarP.location.y) * h)
        let rEar = CGPoint(x: rEarP.location.x * w, y: (1 - rEarP.location.y) * h)
        let lEye = CGPoint(x: lEyeP.location.x * w, y: (1 - lEyeP.location.y) * h)
        let rEye = CGPoint(x: rEyeP.location.x * w, y: (1 - rEyeP.location.y) * h)
        let lSh = CGPoint(x: lShP.location.x * w, y: (1 - lShP.location.y) * h)
        let rSh = CGPoint(x: rShP.location.x * w, y: (1 - rShP.location.y) * h)

        let joints = DetectedJoints(
            nose: CGPoint(x: noseP.location.x, y: 1 - noseP.location.y),
            neck: CGPoint(x: neckP.location.x, y: 1 - neckP.location.y),
            leftEar: CGPoint(x: lEarP.location.x, y: 1 - lEarP.location.y),
            rightEar: CGPoint(x: rEarP.location.x, y: 1 - rEarP.location.y),
            leftEye: CGPoint(x: lEyeP.location.x, y: 1 - lEyeP.location.y),
            rightEye: CGPoint(x: rEyeP.location.x, y: 1 - rEyeP.location.y),
            leftShoulder: CGPoint(x: lShP.location.x, y: 1 - lShP.location.y),
            rightShoulder: CGPoint(x: rShP.location.x, y: 1 - rShP.location.y),
            leftEarConfidence: lEarP.confidence,
            rightEarConfidence: rEarP.confidence
        )

        let earShL = dist(lEar, lSh), earShR = dist(rEar, rSh)
        let eyeShL = dist(lEye, lSh), eyeShR = dist(rEye, rSh)
        let shMid = CGPoint(x: (lSh.x + rSh.x) / 2, y: (lSh.y + rSh.y) / 2)
        let shWidth = dist(lSh, rSh)
        let headFwdRatio = shWidth > 0 ? dist(nose, shMid) / shWidth : 0

        let tiltDx = earsVisible ? rEar.x - lEar.x : rEye.x - lEye.x
        let tiltDy = earsVisible ? rEar.y - lEar.y : rEye.y - lEye.y
        let headTilt = tiltDx != 0 ? atan2(tiltDy, tiltDx) * 180 / .pi : 0

        let earMidY = (lEar.y + rEar.y) / 2
        let earMidX = (lEar.x + rEar.x) / 2
        let vertical = neck.y - earMidY
        let horizontal = abs(earMidX - neck.x)
        let neckEarAngle: CGFloat = vertical > 1 ? min(90, max(10, atan2(vertical, horizontal) * 180 / .pi)) : 10

        if debugCounter % 5 == 0 {
            log(String(format: "[BODY-CVA] earMid=(%.1f,%.1f) neck=(%.1f,%.1f) vert=%.1f horiz=%.1f → CVA=%.1f earConf=%.2f/%.2f",
                earMidX, earMidY, neck.x, neck.y, vertical, horizontal, neckEarAngle,
                lEarP.confidence, rEarP.confidence))
        }

        let metrics = PostureMetrics(
            earShoulderDistanceLeft: earShL, earShoulderDistanceRight: earShR,
            eyeShoulderDistanceLeft: eyeShL, eyeShoulderDistanceRight: eyeShR,
            headForwardRatio: headFwdRatio, headTiltAngle: headTilt,
            neckEarAngle: neckEarAngle,
            shoulderEvenness: abs(lSh.y - rSh.y),
            earsVisible: earsVisible, landmarksDetected: true
        )
        return DetectionResult(metrics: metrics, joints: joints)
    }

    // MARK: - Face Landmarks Fallback

    private func extractFaceResult(from face: VNFaceObservation, imageWidth: Int, imageHeight: Int) -> DetectionResult? {
        let bbox = face.boundingBox
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)

        // Face metrics in Vision normalized coords (bottom-left origin)
        let faceYNorm = bbox.origin.y + bbox.height / 2   // center Y in Vision coords
        let faceHeightNorm = bbox.height
        let pitch = CGFloat(face.pitch?.floatValue ?? 0)   // radians
        let roll = CGFloat(face.roll?.floatValue ?? 0)

        // Use raw per-frame values — no smoothing buffer.
        // PostureEngine's EMA already handles smoothing; double-smoothing here
        // causes stale data to pollute recovery (50° clamp issue).
        let smoothY = faceYNorm
        let smoothHeight = faceHeightNorm
        let smoothPitch = pitch

        // Still update buffers for calibration baseline only
        recentFaceY.append(faceYNorm)
        recentFaceHeight.append(faceHeightNorm)
        recentPitch.append(pitch)
        if recentFaceY.count > smoothingWindow { recentFaceY.removeFirst() }
        if recentFaceHeight.count > smoothingWindow { recentFaceHeight.removeFirst() }
        if recentPitch.count > smoothingWindow { recentPitch.removeFirst() }

        // Face bbox in pixel coords (top-left origin)
        let faceBottom = (1 - bbox.origin.y) * h
        let faceLeft = bbox.origin.x * w
        let faceRight = (bbox.origin.x + bbox.width) * w
        let faceHeight = bbox.height * h
        let faceWidth = bbox.width * w
        let faceCenterX = (faceLeft + faceRight) / 2
        let faceCenterY = (1 - (bbox.origin.y + bbox.height / 2)) * h

        // Extract precise landmark positions
        var nosePos = CGPoint(x: faceCenterX, y: faceCenterY + faceHeight * 0.1)
        var leftEyeCenter = CGPoint(x: faceCenterX - faceWidth * 0.17, y: faceCenterY - faceHeight * 0.08)
        var rightEyeCenter = CGPoint(x: faceCenterX + faceWidth * 0.17, y: faceCenterY - faceHeight * 0.08)
        var chinPos = CGPoint(x: faceCenterX, y: faceBottom)

        if let landmarks = face.landmarks {
            if let noseCrest = landmarks.noseCrest, let tip = noseCrest.normalizedPoints.last {
                nosePos = CGPoint(
                    x: (bbox.origin.x + tip.x * bbox.width) * w,
                    y: (1 - (bbox.origin.y + tip.y * bbox.height)) * h
                )
            }
            if let lEye = landmarks.leftEye {
                let pts = lEye.normalizedPoints
                let avg = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                leftEyeCenter = CGPoint(
                    x: (bbox.origin.x + (avg.x / CGFloat(pts.count)) * bbox.width) * w,
                    y: (1 - (bbox.origin.y + (avg.y / CGFloat(pts.count)) * bbox.height)) * h
                )
            }
            if let rEye = landmarks.rightEye {
                let pts = rEye.normalizedPoints
                let avg = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                rightEyeCenter = CGPoint(
                    x: (bbox.origin.x + (avg.x / CGFloat(pts.count)) * bbox.width) * w,
                    y: (1 - (bbox.origin.y + (avg.y / CGFloat(pts.count)) * bbox.height)) * h
                )
            }
            if let contour = landmarks.faceContour {
                let pts = contour.normalizedPoints
                let chin = pts[pts.count / 2]
                chinPos = CGPoint(
                    x: (bbox.origin.x + chin.x * bbox.width) * w,
                    y: (1 - (bbox.origin.y + chin.y * bbox.height)) * h
                )
            }
        }

        // Estimated joint positions
        let neckPos = CGPoint(x: chinPos.x, y: chinPos.y + faceHeight * 0.2)
        let earY = (leftEyeCenter.y + rightEyeCenter.y) / 2
        let leftEarPos = CGPoint(x: faceLeft - faceWidth * 0.08, y: earY)
        let rightEarPos = CGPoint(x: faceRight + faceWidth * 0.08, y: earY)
        let shoulderSpan = faceWidth * 1.3
        let shoulderY = neckPos.y + faceHeight * 0.35
        let leftShoulderPos = CGPoint(x: faceCenterX - shoulderSpan, y: shoulderY)
        let rightShoulderPos = CGPoint(x: faceCenterX + shoulderSpan, y: shoulderY)

        // === CVA Estimation ===
        // Face proxy for "forward movement" (no Z-depth available):
        //   1. Face drops in frame (Y decreases in Vision coords) = head moves forward & down
        //   2. Face gets larger (bbox height increases) = head moves toward camera = forward
        //   3. Pitch tilts down = chin drops = forward head posture
        //
        // These signals are combined into a forward score, then mapped to CVA angle.

        var forwardScore: CGFloat = 0.0  // 0 = perfect, higher = more forward

        if let baseY = calibratedFaceY, let baseH = calibratedFaceHeight, let baseP = calibratedPitch {
            // Auto-adapt face baseline: if face readings are consistently near baseline
            // (within 0.06 Y), gently nudge baseline toward current readings.
            // This handles systematic offset between body-pose-time and face-only-time.
            let yDiff = abs(smoothY - baseY)
            if yDiff < 0.06 {
                calibratedFaceY = baseY * 0.95 + smoothY * 0.05
                calibratedFaceHeight = baseH * 0.95 + smoothHeight * 0.05
                if smoothPitch != 0 {
                    calibratedPitch = baseP * 0.95 + smoothPitch * 0.05
                }
            }
            let adjBaseY = calibratedFaceY!
            let adjBaseH = calibratedFaceHeight!
            let adjBaseP = calibratedPitch!

            // Signal 1: Face Y drop (head moves forward & down)
            // Dead zone: 0.04 absorbs natural face bbox variance
            let yDrop = adjBaseY - smoothY  // positive = dropped
            let yContrib = yDrop > 0.04 ? (yDrop - 0.04) * 4.0 : 0.0
            forwardScore += yContrib

            // Signal 2: Face getting bigger (leaning toward camera)
            // Dead zone: ignore < 8% size change
            let sizeIncrease = (smoothHeight - adjBaseH) / adjBaseH
            let sizeContrib = sizeIncrease > 0.08 ? (sizeIncrease - 0.08) * 3.0 : 0.0
            forwardScore += sizeContrib

            // Signal 3: Pitch change (head tilting forward)
            let pitchChange = adjBaseP - smoothPitch
            let pitchContrib = pitchChange > 0.08 ? (pitchChange - 0.08) * 3.0 : 0.0
            forwardScore += pitchContrib

            // Signal 4: Face Y rising while pitch drops = chin-poke posture
            let yRise = smoothY - adjBaseY
            if yRise > 0.04 && smoothPitch < adjBaseP - 0.08 {
                forwardScore += yRise * 3.0
            }

            // Debug logging every 3rd frame (~1s at 0.33s interval)
            if debugCounter % 3 == 0 {
                log(String(format: "[FACE] Y:%.4f(base%.4f Δ%.4f) H:%.4f(Δ%.4f) P:%.3f(Δ%.3f) → fwd=%.4f CVA=%.1f",
                      smoothY, adjBaseY, yDrop, smoothHeight, sizeIncrease, smoothPitch, pitchChange, forwardScore,
                      forwardScore < 0.02 ? 65.0 : max(20, min(65, 65.0 - forwardScore * 75.0))))
            }
        }

        // Convert forward score to CVA angle (clinical range)
        // With dead zones, forwardScore stays near 0 for natural jitter.
        // Meaningful movement produces forwardScore 0.05-0.5+
        // Range: 65° (perfect) down to 20° (severe)
        //   0    → 65° (normal, score ~98)
        //   0.05 → 61° (still good, score ~91)
        //   0.20 → 51° (mild, score ~72)
        //   0.40 → 37° (moderate, score ~46)
        //   0.60+→ 20° (severe, score ~14)
        let estimatedCVA: CGFloat
        if forwardScore < 0.02 {
            estimatedCVA = 65.0
        } else {
            let drop = forwardScore * 75.0
            estimatedCVA = max(20, min(65, 65.0 - drop))
        }

        // Normalized joints for skeleton
        let joints = DetectedJoints(
            nose: CGPoint(x: nosePos.x / w, y: nosePos.y / h),
            neck: CGPoint(x: neckPos.x / w, y: neckPos.y / h),
            leftEar: CGPoint(x: leftEarPos.x / w, y: leftEarPos.y / h),
            rightEar: CGPoint(x: rightEarPos.x / w, y: rightEarPos.y / h),
            leftEye: CGPoint(x: leftEyeCenter.x / w, y: leftEyeCenter.y / h),
            rightEye: CGPoint(x: rightEyeCenter.x / w, y: rightEyeCenter.y / h),
            leftShoulder: CGPoint(x: leftShoulderPos.x / w, y: leftShoulderPos.y / h),
            rightShoulder: CGPoint(x: rightShoulderPos.x / w, y: rightShoulderPos.y / h),
            leftEarConfidence: 0.5,
            rightEarConfidence: 0.5
        )

        // Compute metrics
        let earShL = dist(leftEarPos, leftShoulderPos)
        let earShR = dist(rightEarPos, rightShoulderPos)
        let eyeShL = dist(leftEyeCenter, leftShoulderPos)
        let eyeShR = dist(rightEyeCenter, rightShoulderPos)
        let shMid = CGPoint(x: faceCenterX, y: shoulderY)
        let shWidth = dist(leftShoulderPos, rightShoulderPos)
        let headFwdRatio = shWidth > 0 ? dist(nosePos, shMid) / shWidth : 0

        let metrics = PostureMetrics(
            earShoulderDistanceLeft: earShL, earShoulderDistanceRight: earShR,
            eyeShoulderDistanceLeft: eyeShL, eyeShoulderDistanceRight: eyeShR,
            headForwardRatio: headFwdRatio, headTiltAngle: roll * 180 / .pi,
            neckEarAngle: estimatedCVA, shoulderEvenness: 0,
            earsVisible: false, landmarksDetected: true  // false = use CVA-based deviation in PostureAnalyzer
        )

        return DetectionResult(metrics: metrics, joints: joints)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}
