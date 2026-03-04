import Vision
import CoreGraphics
import Foundation

/// Full face mesh data from MediaPipe (478 landmarks + tessellation edges).
/// Landmarks are normalized (0-1). Tessellation edges are static constants.
struct FaceMeshData {
    /// All 478 face landmarks as normalized CGPoints (x, y for screen rendering)
    let landmarks: [CGPoint]
    /// Z-depth per landmark (closer to camera = more negative in MediaPipe convention)
    let depthValues: [CGFloat]

    /// MediaPipe FACEMESH_TESSELATION: 1322 unique edges as (indexA, indexB) pairs.
    /// These are constant — stored here as a static to avoid per-frame allocation.
    static let tessellationEdges: [(Int, Int)] = {
        let flat: [Int] = [
            0,11,0,37,0,164,0,267,1,4,1,19,1,44,1,274,2,94,2,97,2,141,2,164,2,167,2,326,2,370,2,393,3,51,3,195,3,196,3,197,
            3,236,4,5,4,44,4,45,4,51,4,274,4,275,4,281,5,51,5,195,5,281,6,122,6,168,6,196,6,197,6,351,6,419,7,25,7,33,7,110,
            7,163,8,9,8,55,8,168,8,193,8,285,8,417,9,55,9,107,9,108,9,151,9,285,9,336,9,337,10,109,10,151,10,338,11,12,11,37,11,72,
            11,267,11,302,12,13,12,38,12,72,12,268,12,302,13,38,13,82,13,268,13,312,14,15,14,86,14,87,14,316,14,317,15,16,15,85,15,86,15,315,
            15,316,16,17,16,85,16,315,17,18,17,83,17,84,17,85,17,313,17,314,17,315,18,83,18,200,18,201,18,313,18,421,19,44,19,94,19,125,19,141,
            19,274,19,354,19,370,20,60,20,79,20,99,20,166,20,238,20,242,21,54,21,68,21,71,21,162,22,23,22,26,22,145,22,153,22,154,22,230,22,231,
            23,24,23,144,23,145,23,229,23,230,24,110,24,144,24,228,24,229,25,31,25,33,25,110,25,130,25,226,25,228,26,112,26,154,26,155,26,231,26,232,
            27,28,27,29,27,159,27,160,27,222,27,223,28,56,28,157,28,158,28,159,28,221,28,222,29,30,29,160,29,223,29,224,30,160,30,161,30,224,30,225,
            30,247,31,111,31,117,31,226,31,228,32,140,32,171,32,194,32,201,32,208,32,211,33,130,33,246,33,247,34,127,34,139,34,143,34,156,34,227,34,234,
            35,111,35,113,35,124,35,143,35,226,36,100,36,101,36,142,36,203,36,205,36,206,37,39,37,72,37,164,37,167,38,41,38,72,38,81,38,82,39,40,
            39,72,39,73,39,92,39,165,39,167,40,73,40,74,40,92,40,185,40,186,41,42,41,72,41,73,41,74,41,81,42,74,42,80,42,81,42,183,42,184,
            43,57,43,61,43,91,43,106,43,146,43,202,43,204,44,45,44,125,44,220,44,237,45,51,45,134,45,220,46,53,46,63,46,70,46,113,46,124,46,156,
            46,225,47,100,47,114,47,121,47,126,47,128,47,217,48,49,48,64,48,115,48,131,48,219,48,235,49,64,49,102,49,129,49,131,49,209,50,101,50,117,
            50,118,50,123,50,187,50,205,51,134,51,195,51,236,52,53,52,63,52,65,52,66,52,105,52,222,52,223,53,63,53,223,53,224,53,225,54,68,54,103,
            54,104,55,65,55,107,55,189,55,193,55,221,56,157,56,173,56,190,56,221,57,61,57,185,57,186,57,202,57,212,58,132,58,172,58,177,58,215,59,75,
            59,166,59,219,59,235,60,75,60,99,60,166,60,240,61,76,61,146,61,184,61,185,62,76,62,77,62,78,62,96,62,183,62,191,63,68,63,70,63,71,
            63,104,63,105,64,98,64,102,64,129,64,235,64,240,65,66,65,107,65,221,65,222,66,69,66,105,66,107,67,69,67,103,67,104,67,108,67,109,68,71,
            68,104,69,104,69,105,69,107,69,108,70,71,70,139,70,156,71,139,71,162,72,73,73,74,74,184,74,185,75,166,75,235,75,240,76,77,76,146,76,183,
            76,184,77,90,77,91,77,96,77,146,78,95,78,96,78,191,79,166,79,218,79,237,79,238,79,239,80,81,80,183,80,191,81,82,83,84,83,181,83,182,
            83,201,84,85,84,180,84,181,85,86,85,179,85,180,86,87,86,178,86,179,87,178,88,89,88,95,88,96,88,178,88,179,89,90,89,96,89,179,89,180,
            90,91,90,96,90,180,90,181,91,106,91,146,91,181,91,182,92,165,92,186,92,206,92,216,93,132,93,137,93,227,93,234,94,141,94,370,95,96,97,98,
            97,99,97,141,97,165,97,167,97,242,98,99,98,129,98,165,98,203,98,240,99,240,99,242,100,101,100,120,100,121,100,126,100,142,101,118,101,119,101,120,
            101,205,102,129,103,104,104,105,106,182,106,194,106,204,107,108,108,109,108,151,109,151,110,144,110,163,110,228,111,116,111,117,111,123,111,143,111,226,112,133,
            112,155,112,232,112,233,112,243,112,244,113,124,113,225,113,226,113,247,114,128,114,174,114,188,114,217,115,131,115,218,115,219,115,220,116,123,116,137,116,143,
            116,227,117,118,117,123,117,228,117,229,118,119,118,229,118,230,119,120,119,230,120,121,120,230,120,231,120,232,121,128,121,232,122,168,122,188,122,193,122,196,
            122,245,123,137,123,147,123,177,123,187,124,143,124,156,125,141,125,237,125,241,126,129,126,142,126,209,126,217,127,139,127,162,127,234,128,188,128,232,128,233,
            128,245,129,142,129,203,129,209,130,226,130,247,131,134,131,198,131,209,131,220,132,137,132,177,133,155,133,173,133,190,133,243,134,198,134,220,134,236,135,136,
            135,138,135,150,135,169,135,192,135,214,136,138,136,150,136,172,137,177,137,227,138,172,138,192,138,213,138,215,139,156,139,162,140,148,140,170,140,171,140,176,
            140,211,141,241,141,242,142,203,143,156,143,227,144,145,144,163,145,153,147,177,147,187,147,213,147,215,148,152,148,171,148,175,148,176,149,150,149,170,149,176,
            150,169,150,170,151,337,151,338,152,175,152,377,153,154,154,155,157,158,157,173,158,159,159,160,160,161,161,246,161,247,164,167,164,267,164,393,165,167,165,203,
            165,206,166,218,166,219,168,193,168,351,168,417,169,170,169,210,169,211,169,214,170,176,170,211,171,175,171,199,171,208,172,215,173,190,174,188,174,196,174,217,
            174,236,175,199,175,377,175,396,177,215,178,179,179,180,180,181,181,182,182,194,182,201,183,184,183,191,184,185,185,186,186,212,186,216,187,192,187,205,187,207,
            187,213,187,214,188,196,188,245,189,190,189,193,189,221,189,243,189,244,190,221,190,243,192,213,192,214,193,244,193,245,194,201,194,204,194,211,195,197,195,248,
            195,281,196,197,196,236,197,248,197,419,198,209,198,217,198,236,199,200,199,208,199,396,199,428,200,201,200,208,200,421,200,428,201,208,202,204,202,210,202,212,
            202,214,203,206,204,210,204,211,205,206,205,207,205,216,206,216,207,212,207,214,207,216,209,217,210,211,210,214,212,214,212,216,213,215,217,236,218,219,218,220,
            218,237,219,235,220,237,221,222,222,223,223,224,224,225,225,247,226,247,227,234,228,229,229,230,230,231,231,232,232,233,233,244,233,245,235,240,237,239,237,241,
            238,239,238,241,238,242,239,241,241,242,243,244,244,245,246,247,248,281,248,419,248,456,249,255,249,263,249,339,249,390,250,290,250,309,250,328,250,392,250,458,
            250,459,250,462,251,284,251,298,251,301,251,389,252,253,252,256,252,374,252,380,252,381,252,450,252,451,253,254,253,373,253,374,253,449,253,450,254,339,254,373,
            254,448,254,449,255,261,255,263,255,339,255,359,255,446,255,448,256,341,256,381,256,382,256,451,256,452,257,258,257,259,257,386,257,387,257,442,257,443,258,286,
            258,384,258,385,258,386,258,441,258,442,259,260,259,387,259,443,259,444,260,387,260,388,260,444,260,445,260,466,260,467,261,340,261,346,261,446,261,448,262,369,
            262,396,262,418,262,421,262,428,262,431,263,359,263,466,263,467,264,356,264,368,264,372,264,383,264,447,264,454,265,340,265,342,265,353,265,372,265,446,266,329,
            266,330,266,371,266,423,266,425,266,426,267,269,267,302,267,393,268,271,268,302,268,311,268,312,269,270,269,302,269,303,269,322,269,391,269,393,270,303,270,304,
            270,322,270,409,270,410,271,272,271,302,271,303,271,304,271,311,272,304,272,310,272,311,272,407,272,408,273,287,273,291,273,321,273,335,273,375,273,422,273,424,
            274,275,274,354,274,440,274,457,275,281,275,363,275,440,276,283,276,293,276,300,276,342,276,353,276,383,276,445,277,329,277,343,277,350,277,355,277,357,277,437,
            278,279,278,294,278,344,278,360,278,439,278,455,279,294,279,331,279,358,279,360,279,429,280,330,280,346,280,347,280,352,280,411,280,425,281,363,281,456,282,283,
            282,293,282,295,282,296,282,334,282,442,282,443,283,293,283,443,283,444,283,445,284,298,284,332,284,333,285,295,285,336,285,413,285,417,285,441,286,384,286,398,
            286,414,286,441,287,291,287,409,287,410,287,422,287,432,288,361,288,397,288,401,288,435,289,290,289,305,289,392,289,439,289,455,290,305,290,328,290,392,290,460,
            291,306,291,375,291,408,291,409,292,306,292,307,292,308,292,325,292,407,292,415,293,298,293,300,293,301,293,333,293,334,294,327,294,331,294,358,294,455,294,460,
            295,296,295,336,295,441,295,442,296,299,296,334,296,336,297,299,297,332,297,333,297,337,297,338,298,301,298,333,299,333,299,334,299,336,299,337,300,301,300,368,
            300,383,301,368,301,389,302,303,303,304,304,408,304,409,305,455,305,460,306,307,306,375,306,407,306,408,307,320,307,321,307,325,307,375,308,324,308,325,308,415,
            309,392,309,438,309,457,309,459,310,311,310,407,310,415,311,312,313,314,313,405,313,406,313,421,314,315,314,404,314,405,315,316,315,403,315,404,316,317,316,402,
            316,403,317,402,318,319,318,324,318,325,318,402,318,403,319,320,319,325,319,403,319,404,320,321,320,325,320,404,320,405,321,335,321,375,321,405,321,406,322,391,
            322,410,322,426,322,436,323,361,323,366,323,447,323,454,324,325,326,327,326,328,326,370,326,391,326,393,326,462,327,328,327,358,327,391,327,423,327,460,328,460,
            328,462,329,330,329,349,329,350,329,355,329,371,330,347,330,348,330,349,330,425,331,358,332,333,333,334,335,406,335,418,335,424,336,337,337,338,339,373,339,390,
            339,448,340,345,340,346,340,352,340,372,340,446,341,362,341,382,341,452,341,453,341,463,341,464,342,353,342,445,342,446,342,467,343,357,343,399,343,412,343,437,
            344,360,344,438,344,439,344,440,345,352,345,366,345,372,345,447,346,347,346,352,346,448,346,449,347,348,347,449,347,450,348,349,348,450,349,350,349,450,349,451,
            349,452,350,357,350,452,351,412,351,417,351,419,351,465,352,366,352,376,352,401,352,411,353,372,353,383,354,370,354,457,354,461,355,358,355,371,355,429,355,437,
            356,368,356,389,356,454,357,412,357,452,357,453,357,465,358,371,358,423,358,429,359,446,359,467,360,363,360,420,360,429,360,440,361,366,361,401,362,382,362,398,
            362,414,362,463,363,420,363,440,363,456,364,365,364,367,364,379,364,394,364,416,364,434,365,367,365,379,365,397,366,401,366,447,367,397,367,416,367,433,367,435,
            368,383,368,389,369,377,369,395,369,396,369,400,369,431,370,461,370,462,371,423,372,383,372,447,373,374,373,390,374,380,376,401,376,411,376,433,376,435,377,396,
            377,400,378,379,378,395,378,400,379,394,379,395,380,381,381,382,384,385,384,398,385,386,386,387,387,388,388,466,391,393,391,423,391,426,392,438,392,439,394,395,
            394,430,394,431,394,434,395,400,395,431,396,428,397,435,398,414,399,412,399,419,399,437,399,456,401,435,402,403,403,404,404,405,405,406,406,418,406,421,407,408,
            407,415,408,409,409,410,410,432,410,436,411,416,411,425,411,427,411,433,411,434,412,419,412,465,413,414,413,417,413,441,413,463,413,464,414,441,414,463,416,433,
            416,434,417,464,417,465,418,421,418,424,418,431,419,456,420,429,420,437,420,456,421,428,422,424,422,430,422,432,422,434,423,426,424,430,424,431,425,426,425,427,
            425,436,426,436,427,432,427,434,427,436,429,437,430,431,430,434,432,434,432,436,433,435,437,456,438,439,438,440,438,457,439,455,440,457,441,442,442,443,443,444,
            444,445,445,467,446,467,447,454,448,449,449,450,450,451,451,452,452,453,453,464,453,465,455,460,457,459,457,461,458,459,458,461,458,462,459,461,461,462,463,464,
            464,465,466,467
        ]
        var edges: [(Int, Int)] = []
        edges.reserveCapacity(flat.count / 2)
        for i in stride(from: 0, to: flat.count, by: 2) {
            edges.append((flat[i], flat[i + 1]))
        }
        return edges
    }()
}

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

    var leftWrist: CGPoint? = nil
    var rightWrist: CGPoint? = nil

    // Optional face mesh data from MediaPipe (nil when using Vision fallback)
    var faceMesh: FaceMeshData? = nil

    var allPoints: [(name: String, point: CGPoint)] {
        var points: [(name: String, point: CGPoint)] = [
            ("nose", nose), ("neck", neck),
            ("leftEar", leftEar), ("rightEar", rightEar),
            ("leftEye", leftEye), ("rightEye", rightEye),
            ("leftShoulder", leftShoulder), ("rightShoulder", rightShoulder),
        ]
        if let leftWrist {
            points.append(("leftWrist", leftWrist))
        }
        if let rightWrist {
            points.append(("rightWrist", rightWrist))
        }
        return points
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
    private static let maxReliableYawDegrees: CGFloat = 15

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
    private var lastReliableCVA: CGFloat?
    private var lastFaceFallbackCVA: CGFloat?
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
        let faceObservation = faceReq.results?.first

        // Priority 1: 2D body pose (stable neckEarAngle from ear-neck geometry)
        let bodyResults = body2DReq.results ?? []
        if debugCounter % 10 == 0 { log("[BODY] results=\(bodyResults.count)") }
        if let bodyObs = bodyResults.first,
           let bodyResult = try? extractBodyResult(
            from: bodyObs,
            imageWidth: image.width,
            imageHeight: image.height,
            faceYawRadians: yawRadians(from: faceObservation),
            faceObservation: faceObservation
           ) {
            if debugCounter % 10 == 0 { log("[PATH] 2D body pose → CVA=\(String(format: "%.1f", bodyResult.metrics.neckEarAngle))") }
            debugCounter += 1
            // Clear face smoothing buffers so stale face data doesn't pollute
            // the next face fallback transition
            recentFaceY.removeAll()
            recentFaceHeight.removeAll()
            recentPitch.removeAll()
            // Reset face fallback slew limiter when not using fallback path.
            lastFaceFallbackCVA = nil
            return bodyResult
        }

        // Priority 2: Face landmarks fallback
        if let faceObs = faceObservation {
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
        lastFaceFallbackCVA = nil
    }

    /// Clear face calibration baseline (called when user resets calibration).
    func resetFaceBaseline() {
        calibratedFaceY = nil
        calibratedFaceHeight = nil
        calibratedPitch = nil
        recentFaceY.removeAll()
        recentFaceHeight.removeAll()
        recentPitch.removeAll()
        lastReliableCVA = nil
        lastFaceFallbackCVA = nil
    }

    // MARK: - 2D Body Pose Detection

    private func extractBodyResult(
        from observation: VNHumanBodyPoseObservation,
        imageWidth: Int,
        imageHeight: Int,
        faceYawRadians: CGFloat?,
        faceObservation: VNFaceObservation?
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
        let lWristP = try? observation.recognizedPoint(.leftWrist)
        let rWristP = try? observation.recognizedPoint(.rightWrist)

        guard neckP.confidence > 0.1, lShP.confidence > 0.1, rShP.confidence > 0.1 else {
            if debugCounter % 10 == 0 {
                log(String(format: "[BODY] low confidence: neck=%.2f lSh=%.2f rSh=%.2f",
                    neckP.confidence, lShP.confidence, rShP.confidence))
            }
            return nil
        }

        let earsVisible = lEarP.confidence > Self.earVisibilityThreshold
            && rEarP.confidence > Self.earVisibilityThreshold
        let yawDegrees = abs((faceYawRadians ?? 0) * 180 / .pi)
        let yawReliable = faceYawRadians == nil || yawDegrees <= Self.maxReliableYawDegrees
        let yawFactor = sagittalYawFactor(yawRadians: faceYawRadians)
        let confidenceScale: Float = yawReliable ? 1.0 : 0.25
        let faceSizeNormalized = faceObservation?.boundingBox.height ?? 0

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
            leftEarConfidence: lEarP.confidence * confidenceScale,
            rightEarConfidence: rEarP.confidence * confidenceScale,
            leftWrist: lWristP.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) },
            rightWrist: rWristP.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
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
        let sagittalForward = horizontal * yawFactor
        var neckEarAngle: CGFloat = vertical > 1 ? min(90, max(10, atan2(vertical, max(1e-6, sagittalForward)) * 180 / .pi)) : 10

        if !yawReliable {
            if let lastReliableCVA {
                neckEarAngle = lastReliableCVA
            }
        } else {
            lastReliableCVA = neckEarAngle
        }

        if debugCounter % 5 == 0 {
            log(String(format: "[BODY-CVA] earMid=(%.1f,%.1f) neck=(%.1f,%.1f) vert=%.1f horiz=%.1f sag=%.1f yaw=%.1f° → CVA=%.1f earConf=%.2f/%.2f",
                earMidX, earMidY, neck.x, neck.y, vertical, horizontal, sagittalForward, yawDegrees, neckEarAngle,
                lEarP.confidence, rEarP.confidence))
        }

        let metrics = PostureMetrics(
            earShoulderDistanceLeft: earShL, earShoulderDistanceRight: earShR,
            eyeShoulderDistanceLeft: eyeShL, eyeShoulderDistanceRight: eyeShR,
            headForwardRatio: headFwdRatio, headTiltAngle: headTilt,
            neckEarAngle: neckEarAngle,
            headPitch: CGFloat(faceObservation?.pitch?.floatValue ?? 0),
            faceSizeNormalized: faceSizeNormalized,
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
        let yaw = CGFloat(face.yaw?.floatValue ?? 0)
        let roll = CGFloat(face.roll?.floatValue ?? 0)
        let yawDegrees = abs(yaw * 180 / .pi)
        let yawReliable = yawDegrees <= Self.maxReliableYawDegrees
        let yawFactor = sagittalYawFactor(yawRadians: yaw)

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
            if yDiff < 0.06 && yawReliable {
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
            let yDrop = (adjBaseY - smoothY) * yawFactor  // positive = dropped
            let yContrib = yDrop > 0.04 ? (yDrop - 0.04) * 4.0 : 0.0
            forwardScore += yContrib

            // Signal 2: Face getting bigger (leaning toward camera)
            // Dead zone: ignore < 8% size change
            let sizeIncrease = ((smoothHeight - adjBaseH) / adjBaseH) * yawFactor
            let sizeContrib = sizeIncrease > 0.08 ? (sizeIncrease - 0.08) * 3.0 : 0.0
            forwardScore += sizeContrib

            // Signal 3: Pitch change (head tilting forward)
            let pitchChange = adjBaseP - smoothPitch
            let pitchContrib = pitchChange > 0.08 ? (pitchChange - 0.08) * 1.5 : 0.0
            forwardScore += pitchContrib

            // Signal 4: Face Y rising while pitch drops = chin-poke posture
            let yRise = (smoothY - adjBaseY) * yawFactor
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
        var estimatedCVA: CGFloat
        if forwardScore < 0.02 {
            estimatedCVA = 65.0
        } else {
            let drop = forwardScore * 75.0
            estimatedCVA = max(20, min(65, 65.0 - drop))
        }

        if !yawReliable {
            if let lastReliableCVA {
                estimatedCVA = lastReliableCVA
            }
        } else {
            lastReliableCVA = estimatedCVA
        }

        // Face fallback only: limit per-frame CVA jump to filter expression-driven spikes.
        let maxDelta: CGFloat = 3.0
        if let previous = lastFaceFallbackCVA {
            let delta = estimatedCVA - previous
            let clampedDelta = max(-maxDelta, min(maxDelta, delta))
            estimatedCVA = previous + clampedDelta
        }
        lastFaceFallbackCVA = estimatedCVA

        // Normalized joints for skeleton
        let faceConfidence: Float = yawReliable ? 0.5 : 0.1
        let joints = DetectedJoints(
            nose: CGPoint(x: nosePos.x / w, y: nosePos.y / h),
            neck: CGPoint(x: neckPos.x / w, y: neckPos.y / h),
            leftEar: CGPoint(x: leftEarPos.x / w, y: leftEarPos.y / h),
            rightEar: CGPoint(x: rightEarPos.x / w, y: rightEarPos.y / h),
            leftEye: CGPoint(x: leftEyeCenter.x / w, y: leftEyeCenter.y / h),
            rightEye: CGPoint(x: rightEyeCenter.x / w, y: rightEyeCenter.y / h),
            leftShoulder: CGPoint(x: leftShoulderPos.x / w, y: leftShoulderPos.y / h),
            rightShoulder: CGPoint(x: rightShoulderPos.x / w, y: rightShoulderPos.y / h),
            leftEarConfidence: faceConfidence,
            rightEarConfidence: faceConfidence
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
            neckEarAngle: estimatedCVA,
            headPitch: pitch,
            faceSizeNormalized: faceHeightNorm,
            shoulderEvenness: 0,
            earsVisible: false, landmarksDetected: true  // false = use CVA-based deviation in PostureAnalyzer
        )

        return DetectionResult(metrics: metrics, joints: joints)
    }

    private func yawRadians(from faceObservation: VNFaceObservation?) -> CGFloat? {
        guard let faceObservation else { return nil }
        guard let yawValue = faceObservation.yaw?.doubleValue else { return nil }
        return CGFloat(yawValue)
    }

    private func sagittalYawFactor(yawRadians: CGFloat?) -> CGFloat {
        guard let yawRadians else { return 1.0 }
        let clamped = min(abs(yawRadians), .pi / 2)
        return max(0.0, cos(clamped))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}
