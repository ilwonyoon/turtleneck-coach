import AppKit
import CoreGraphics
import Foundation

/// Result from the Python MediaPipe pose server.
struct MediaPipeResult: Codable {
    let headPitch: Double
    let headYaw: Double
    let headRoll: Double
    let earLeft: [Double]
    let earRight: [Double]
    let shoulderLeft: [Double]
    let shoulderRight: [Double]
    let nose: [Double]
    let neckMid: [Double]
    let leftEye: [Double]
    let rightEye: [Double]
    let cvaAngle: Double
    let confidence: Double
    let forwardDepth: Double?
    let irisGazeOffset: Double?
    let yawLowConfidence: Bool?
    let frameNumber: Int?
    /// All 478 face landmarks as flat array [x0,y0,z0,x1,y1,z1,...] (3D with depth)
    let faceLandmarks: [Double]?

    enum CodingKeys: String, CodingKey {
        case headPitch = "head_pitch"
        case headYaw = "head_yaw"
        case headRoll = "head_roll"
        case earLeft = "ear_left"
        case earRight = "ear_right"
        case shoulderLeft = "shoulder_left"
        case shoulderRight = "shoulder_right"
        case nose
        case neckMid = "neck_mid"
        case leftEye = "left_eye"
        case rightEye = "right_eye"
        case cvaAngle = "cva_angle"
        case confidence
        case forwardDepth = "forward_depth"
        case irisGazeOffset = "iris_gaze_offset"
        case yawLowConfidence = "yaw_low_confidence"
        case frameNumber = "frame_number"
        case faceLandmarks = "face_landmarks"
    }
}

/// Manages connection to the Python MediaPipe pose server via Unix Domain Socket.
/// Also handles Python subprocess lifecycle.
final class MediaPipeClient: @unchecked Sendable {

    private let socketPath = "/tmp/pt_turtle.sock"
    private var fileHandle: FileHandle?
    private var socketFD: Int32 = -1
    private var pythonProcess: Process?
    private let queue = DispatchQueue(label: "mediapipe.client", qos: .userInitiated)
    private var _isConnected = false
    private var lastReliableCVA: CGFloat?

    var isConnected: Bool { _isConnected }

    // MARK: - Python Process Management

    /// Find the pose_server.py script and its directory.
    /// Uses ~/.pt_turtle/server/ to avoid ~/Documents TCC permission prompts.
    private func findServerScript() -> (script: String, dir: String)? {
        let candidates = [
            // Primary: user-local install (no TCC permission needed)
            NSHomeDirectory() + "/.pt_turtle/server/pose_server.py",
            // Dev mode: relative to project source (when launched from Xcode)
            Bundle.main.bundlePath + "/../python_server/pose_server.py",
            // Bundled inside .app
            Bundle.main.bundlePath + "/Contents/Resources/python_server/pose_server.py",
            // CWD (for development)
            "./python_server/pose_server.py",
        ]

        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                let dir = (resolved as NSString).deletingLastPathComponent
                return (resolved, dir)
            }
        }
        return nil
    }

    /// Find python3 executable — prefer venv next to pose_server.py.
    private func findPython(serverDir: String) -> String {
        let venvPython = (serverDir as NSString).appendingPathComponent(".venv/bin/python3")
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        return "/usr/bin/env"
    }

    /// Start the Python MediaPipe server process.
    private func startPythonServer() -> Bool {
        guard pythonProcess == nil || pythonProcess?.isRunning != true else {
            return true
        }

        guard let serverInfo = findServerScript() else {
            log("Cannot find pose_server.py")
            return false
        }

        let pythonPath = findPython(serverDir: serverInfo.dir)
        let process = Process()

        if pythonPath == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", serverInfo.script]
        } else {
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [serverInfo.script]
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            pythonProcess = process
            log("Started Python server (PID \(process.processIdentifier))")
            // Give server time to start listening
            Thread.sleep(forTimeInterval: 1.5)
            return true
        } catch {
            log("Failed to start Python server: \(error)")
            return false
        }
    }

    /// Stop the Python server process.
    private func stopPythonServer() {
        guard let process = pythonProcess, process.isRunning else { return }
        process.terminate()
        pythonProcess = nil
        log("Stopped Python server")
    }

    // MARK: - Connection Management

    /// Connect to the Python server via Unix Domain Socket.
    func connect() -> Bool {
        // Start Python server if needed
        if !FileManager.default.fileExists(atPath: socketPath) {
            guard startPythonServer() else { return false }
        }

        // Create Unix domain socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log("Failed to create socket: \(String(cString: strerror(errno)))")
            return false
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104)
                    dest.update(from: src.baseAddress!, count: count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + socketPath.utf8.count + 1)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        if result < 0 {
            close(fd)
            // Try starting server and retrying
            if startPythonServer() {
                return retryConnect()
            }
            log("Failed to connect: \(String(cString: strerror(errno)))")
            return false
        }

        socketFD = fd
        _isConnected = true
        log("Connected to pose server")
        return true
    }

    private func retryConnect() -> Bool {
        for attempt in 1...3 {
            Thread.sleep(forTimeInterval: Double(attempt) * 0.5)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = socketPath.utf8CString
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                    pathBytes.withUnsafeBufferPointer { src in
                        let count = min(src.count, 104)
                        dest.update(from: src.baseAddress!, count: count)
                    }
                }
            }

            let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + socketPath.utf8.count + 1)
            let result = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(fd, sockaddrPtr, addrLen)
                }
            }

            if result == 0 {
                socketFD = fd
                _isConnected = true
                log("Connected on retry \(attempt)")
                return true
            }
            close(fd)
        }
        log("Failed to connect after retries")
        return false
    }

    /// Disconnect from the server.
    func disconnect() {
        _isConnected = false
        lastReliableCVA = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        fileHandle = nil
    }

    /// Disconnect and stop the Python process.
    func shutdown() {
        // Try sending shutdown message
        if _isConnected {
            _ = sendRaw(data: "SHUTDOWN".data(using: .utf8)!)
        }
        disconnect()
        stopPythonServer()
    }

    // MARK: - Frame Communication

    /// Send a CGImage frame and receive MediaPipeResult.
    func sendFrame(_ image: CGImage) -> MediaPipeResult? {
        guard _isConnected, socketFD >= 0 else { return nil }

        // Convert CGImage to JPEG data
        guard let jpegData = jpegData(from: image, quality: 0.7) else { return nil }

        // Send length-prefixed JPEG
        guard sendRaw(data: jpegData) else {
            _isConnected = false
            return nil
        }

        // Receive length-prefixed JSON response
        guard let responseData = receiveRaw() else {
            _isConnected = false
            return nil
        }

        // Parse JSON
        do {
            let result = try JSONDecoder().decode(MediaPipeResult.self, from: responseData)
            if let fl = result.faceLandmarks {
                log("faceLandmarks count=\(fl.count) (need 1434 for 3D mesh)")
            } else {
                log("faceLandmarks=nil")
            }
            return result
        } catch {
            log("JSON decode error: \(error)")
            return nil
        }
    }

    // MARK: - Low-Level Socket IO

    private func sendRaw(data: Data) -> Bool {
        var length = UInt32(data.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)

        let headerSent = lengthData.withUnsafeBytes { ptr in
            send(socketFD, ptr.baseAddress!, 4, 0)
        }
        guard headerSent == 4 else { return false }

        let bodySent = data.withUnsafeBytes { ptr in
            send(socketFD, ptr.baseAddress!, data.count, 0)
        }
        return bodySent == data.count
    }

    private func receiveRaw() -> Data? {
        // Read 4-byte length header
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        var totalRead = 0
        while totalRead < 4 {
            let n = lengthBytes.withUnsafeMutableBufferPointer { buf in
                recv(socketFD, buf.baseAddress! + totalRead, 4 - totalRead, 0)
            }
            if n <= 0 { return nil }
            totalRead += n
        }

        let length = Int(UInt32(bigEndian: lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length > 0, length < 10_000_000 else { return nil }

        // Read body
        var body = [UInt8](repeating: 0, count: length)
        totalRead = 0
        while totalRead < length {
            let n = body.withUnsafeMutableBufferPointer { buf in
                recv(socketFD, buf.baseAddress! + totalRead, length - totalRead, 0)
            }
            if n <= 0 { return nil }
            totalRead += n
        }

        return Data(body)
    }

    // MARK: - Helpers

    private func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }

    private func log(_ msg: String) {
        let line = "\(Date()): [MediaPipeClient] \(msg)\n"
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

    /// Convert a MediaPipeResult into DetectedJoints for skeleton rendering.
    func resultToJoints(_ result: MediaPipeResult) -> DetectedJoints {
        let nose = CGPoint(x: result.nose[0], y: result.nose[1])
        let neck = CGPoint(x: result.neckMid[0], y: result.neckMid[1])
        let lEar = CGPoint(x: result.earLeft[0], y: result.earLeft[1])
        let rEar = CGPoint(x: result.earRight[0], y: result.earRight[1])
        let lEye = CGPoint(x: result.leftEye[0], y: result.leftEye[1])
        let rEye = CGPoint(x: result.rightEye[0], y: result.rightEye[1])
        let lSh = CGPoint(x: result.shoulderLeft[0], y: result.shoulderLeft[1])
        let rSh = CGPoint(x: result.shoulderRight[0], y: result.shoulderRight[1])

        // Build face mesh data from all 478 landmarks (flat array: [x0,y0,z0,x1,y1,z1,...])
        var meshData: FaceMeshData? = nil
        if let flat = result.faceLandmarks, flat.count >= 1434 {  // 478 * 3
            var landmarks = [CGPoint]()
            var depths = [CGFloat]()
            landmarks.reserveCapacity(478)
            depths.reserveCapacity(478)
            for i in stride(from: 0, to: 1434, by: 3) {
                landmarks.append(CGPoint(x: flat[i], y: flat[i + 1]))
                depths.append(CGFloat(flat[i + 2]))
            }
            meshData = FaceMeshData(landmarks: landmarks, depthValues: depths)
        }

        return DetectedJoints(
            nose: nose,
            neck: neck,
            leftEar: lEar,
            rightEar: rEar,
            leftEye: lEye,
            rightEye: rEye,
            leftShoulder: lSh,
            rightShoulder: rSh,
            leftEarConfidence: Float(result.confidence),
            rightEarConfidence: Float(result.confidence),
            faceMesh: meshData
        )
    }

    /// Convert a MediaPipeResult into PostureMetrics.
    func resultToMetrics(_ result: MediaPipeResult, imageWidth: Int, imageHeight: Int) -> PostureMetrics {
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)

        let lEar = CGPoint(x: CGFloat(result.earLeft[0]) * w, y: CGFloat(result.earLeft[1]) * h)
        let rEar = CGPoint(x: CGFloat(result.earRight[0]) * w, y: CGFloat(result.earRight[1]) * h)
        let lEye = CGPoint(x: CGFloat(result.leftEye[0]) * w, y: CGFloat(result.leftEye[1]) * h)
        let rEye = CGPoint(x: CGFloat(result.rightEye[0]) * w, y: CGFloat(result.rightEye[1]) * h)
        let neckMid = CGPoint(x: CGFloat(result.neckMid[0]) * w, y: CGFloat(result.neckMid[1]) * h)
        let lSh = CGPoint(x: CGFloat(result.shoulderLeft[0]) * w, y: CGFloat(result.shoulderLeft[1]) * h)
        let rSh = CGPoint(x: CGFloat(result.shoulderRight[0]) * w, y: CGFloat(result.shoulderRight[1]) * h)
        let nosePos = CGPoint(x: CGFloat(result.nose[0]) * w, y: CGFloat(result.nose[1]) * h)

        let earShL = dist(lEar, lSh)
        let earShR = dist(rEar, rSh)
        let eyeShL = dist(lEye, lSh)
        let eyeShR = dist(rEye, rSh)
        let shMid = CGPoint(x: (lSh.x + rSh.x) / 2, y: (lSh.y + rSh.y) / 2)
        let shWidth = dist(lSh, rSh)
        let yawDegrees = abs(CGFloat(result.headYaw))
        let yawLowConfidence = result.yawLowConfidence ?? (yawDegrees > 15)
        let yawFactor = sagittalYawFactor(yawDegrees: yawDegrees)
        let horizontalDist = abs(nosePos.x - shMid.x)
        let sagittalForward = horizontalDist * yawFactor
        let headFwdRatio = shWidth > 0 ? sagittalForward / shWidth : 0

        let tiltDx = rEar.x - lEar.x
        let tiltDy = rEar.y - lEar.y
        let headTilt = tiltDx != 0 ? atan2(tiltDy, tiltDx) * 180 / .pi : 0
        let eyeMidY = (lEye.y + rEye.y) / 2
        let chinY = neckMid.y
        let faceSizeNormalized = h > 0 ? abs(chinY - eyeMidY) / h : 0
        var neckEarAngle = CGFloat(result.cvaAngle)
        if yawLowConfidence {
            if let lastReliableCVA {
                neckEarAngle = lastReliableCVA
            }
        } else {
            lastReliableCVA = neckEarAngle
        }

        let effectiveConfidence = yawLowConfidence ? min(result.confidence, 0.2) : result.confidence

        return PostureMetrics(
            earShoulderDistanceLeft: earShL,
            earShoulderDistanceRight: earShR,
            eyeShoulderDistanceLeft: eyeShL,
            eyeShoulderDistanceRight: eyeShR,
            headForwardRatio: headFwdRatio,
            headTiltAngle: headTilt,
            neckEarAngle: neckEarAngle,
            headPitch: CGFloat(result.headPitch),
            faceSizeNormalized: faceSizeNormalized,
            shoulderEvenness: abs(lSh.y - rSh.y),
            earsVisible: effectiveConfidence > 0.3,
            landmarksDetected: effectiveConfidence > 0.1,
            forwardDepth: CGFloat(result.forwardDepth ?? 0),
            irisGazeOffset: CGFloat(result.irisGazeOffset ?? 0)
        )
    }

    private func sagittalYawFactor(yawDegrees: CGFloat) -> CGFloat {
        let clampedRadians = min(abs(yawDegrees) * .pi / 180, .pi / 2)
        return max(0.0, cos(clampedRadians))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}
