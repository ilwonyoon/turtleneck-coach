import AppKit
import CoreGraphics
import Foundation
import os

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
    private struct ServerScriptLocation {
        let script: String
        let dir: String
        let source: String
        let bundled: Bool
    }

    private struct PythonLaunch {
        let executable: String
        let argumentsPrefix: [String]
        let source: String
    }

    private struct BundledPythonLayout {
        let runtimeRoot: String
        let executable: String
        let pythonHome: String
        let pythonPathEntries: [String]
        let dylibDirectories: [String]
        let source: String
    }

    private let socketPath = "/tmp/pt_turtle.sock"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.turtleneck.detector",
        category: "MediaPipeClient"
    )
    private let requiredServerRelativePaths = [
        "pose_server.py",
        "models/pose_landmarker_lite.task",
        "models/face_landmarker.task",
    ]
    private var fileHandle: FileHandle?
    private var socketFD: Int32 = -1
    private var pythonProcess: Process?
    private let queue = DispatchQueue(label: "mediapipe.client", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queueKeyValue: UInt8 = 1
    private var _isConnected = false
    private var lastReliableCVA: CGFloat?

    init() {
        queue.setSpecific(key: queueKey, value: queueKeyValue)
    }

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) == queueKeyValue
    }

    var isConnected: Bool {
        if isOnQueue { return _isConnected }
        return queue.sync { _isConnected }
    }

    // MARK: - Python Process Management

    private var bundledPythonServerScript: String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python_server", isDirectory: true)
            .appendingPathComponent("pose_server.py")
            .path
    }

    private var bundledPythonRuntime: String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python_runtime", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
            .path
    }

    private var bundledPythonRuntimeRoot: String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python_runtime", isDirectory: true)
            .path
    }

    private var bundledPythonPackagesRoot: String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("python_packages", isDirectory: true)
            .path
    }

    private func bundledPythonSitePackages() -> String? {
        guard let packagesRoot = bundledPythonPackagesRoot else { return nil }
        let libRoot = (packagesRoot as NSString).appendingPathComponent("lib")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: libRoot) else {
            return nil
        }

        for entry in entries.sorted() {
            guard entry.hasPrefix("python") else { continue }
            let sitePackages = ((libRoot as NSString).appendingPathComponent(entry) as NSString)
                .appendingPathComponent("site-packages")
            if FileManager.default.fileExists(atPath: sitePackages) {
                return sitePackages
            }
        }

        return nil
    }

    private func versionedPythonDirectories(in libRoot: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: libRoot) else {
            return []
        }

        return entries.sorted().compactMap { entry in
            guard entry.hasPrefix("python") else { return nil }
            let candidate = (libRoot as NSString).appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return (candidate as NSString).standardizingPath
        }
    }

    private func versionedPythonZipArchives(in libRoot: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: libRoot) else {
            return []
        }

        return entries.sorted().compactMap { entry in
            guard entry.hasPrefix("python"), entry.hasSuffix(".zip") else { return nil }
            let candidate = (libRoot as NSString).appendingPathComponent(entry)
            guard FileManager.default.fileExists(atPath: candidate) else { return nil }
            return (candidate as NSString).standardizingPath
        }
    }

    private func bundledDylibDirectories(in runtimeRoot: String) -> [String] {
        let fileManager = FileManager.default
        let candidateDirs = [
            (runtimeRoot as NSString).appendingPathComponent("lib"),
            (runtimeRoot as NSString).appendingPathComponent("Python.framework/Versions/Current"),
            (runtimeRoot as NSString).appendingPathComponent("Frameworks/Python.framework/Versions/Current"),
        ]

        return candidateDirs.compactMap { candidateDir in
            guard let entries = try? fileManager.contentsOfDirectory(atPath: candidateDir) else { return nil }
            return entries.contains(where: { $0.hasPrefix("libpython3") && $0.hasSuffix(".dylib") })
                ? (candidateDir as NSString).standardizingPath
                : nil
        }
    }

    private func uniqueExistingPaths(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []

        for candidate in candidates {
            let resolved = (candidate as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: resolved), !seen.contains(resolved) else { continue }
            seen.insert(resolved)
            results.append(resolved)
        }

        return results
    }

    private func joinedEnvironmentPath(existing: String?, prepending entries: [String]) -> String? {
        let cleaned = entries.filter { !$0.isEmpty }
        let existingEntries = (existing ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        let allEntries = uniqueExistingPaths(cleaned + existingEntries)
        return allEntries.isEmpty ? nil : allEntries.joined(separator: ":")
    }

    private func bundledStdlibEntries(runtimeRoot: String) -> [String] {
        let libRoot = (runtimeRoot as NSString).appendingPathComponent("lib")
        let frameworkLibRoots = [
            (runtimeRoot as NSString).appendingPathComponent("Python.framework/Versions/Current/lib"),
            (runtimeRoot as NSString).appendingPathComponent("Frameworks/Python.framework/Versions/Current/lib"),
        ]
        let stdlibCandidates = [libRoot] + frameworkLibRoots
        return uniqueExistingPaths(stdlibCandidates.flatMap { candidateRoot in
            versionedPythonZipArchives(in: candidateRoot) + versionedPythonDirectories(in: candidateRoot)
        })
    }

    private func bundledPythonPathEntries(runtimeRoot: String) -> [String] {
        let stdlibEntries = bundledStdlibEntries(runtimeRoot: runtimeRoot)
        let runtimeSitePackages = stdlibEntries.compactMap { entry -> String? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: entry, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return (entry as NSString).appendingPathComponent("site-packages")
        }
        let packageEntries = bundledPythonSitePackages().map { [$0] } ?? []
        return uniqueExistingPaths(stdlibEntries + runtimeSitePackages + packageEntries)
    }

    private func resolveBundledPythonLayout() -> BundledPythonLayout? {
        guard
            let runtimeRoot = bundledPythonRuntimeRoot.map({ ($0 as NSString).standardizingPath }),
            let executable = bundledPythonRuntime.map({ ($0 as NSString).standardizingPath }),
            FileManager.default.fileExists(atPath: executable)
        else {
            return nil
        }

        let stdlibEntries = bundledStdlibEntries(runtimeRoot: runtimeRoot)
        let pythonPathEntries = bundledPythonPathEntries(runtimeRoot: runtimeRoot)
        let dylibDirectories = bundledDylibDirectories(in: runtimeRoot)
        let hasVendoredStdlib = !stdlibEntries.isEmpty

        guard hasVendoredStdlib else {
            let checked = [
                (runtimeRoot as NSString).appendingPathComponent("lib"),
                (runtimeRoot as NSString).appendingPathComponent("Python.framework/Versions/Current/lib"),
                (runtimeRoot as NSString).appendingPathComponent("Frameworks/Python.framework/Versions/Current/lib"),
                bundledPythonPackagesRoot ?? "",
            ]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            log("Bundled Python runtime missing vendored stdlib under python_runtime. Checked: \(checked)")
            return nil
        }

        return BundledPythonLayout(
            runtimeRoot: runtimeRoot,
            executable: executable,
            pythonHome: runtimeRoot,
            pythonPathEntries: pythonPathEntries,
            dylibDirectories: dylibDirectories,
            source: "bundled-runtime"
        )
    }

    private func missingRelativePaths(in serverDir: String) -> [String] {
        requiredServerRelativePaths.filter { relativePath in
            let candidate = (serverDir as NSString).appendingPathComponent(relativePath)
            return !FileManager.default.fileExists(atPath: candidate)
        }
    }

    private func releaseRuntimeCandidates(serverDir: String) -> [String] {
        var candidates: [String] = []
        if let bundledRuntime = bundledPythonRuntime {
            candidates.append((bundledRuntime as NSString).standardizingPath)
        }
        if let bundledRoot = bundledPythonRuntimeRoot {
            candidates.append((bundledRoot as NSString).appendingPathComponent("lib"))
        }
        #if DEBUG
        candidates.append((serverDir as NSString).appendingPathComponent(".venv/bin/python3"))
        #endif
        return candidates
    }

    private func releasePackageCandidates() -> [String] {
        var candidates: [String] = []
        if let bundledRoot = bundledPythonRuntimeRoot {
            candidates.append((bundledRoot as NSString).appendingPathComponent("lib"))
        }
        if let bundledSitePackages = bundledPythonSitePackages() {
            candidates.append((bundledSitePackages as NSString).standardizingPath)
        } else if let bundledRoot = bundledPythonPackagesRoot {
            candidates.append((bundledRoot as NSString).standardizingPath)
        }
        return candidates
    }

    private func validateServerLayout(_ serverInfo: ServerScriptLocation) -> Bool {
        let missing = missingRelativePaths(in: serverInfo.dir)
        guard missing.isEmpty else {
            let missingText = missing.joined(separator: ", ")
            log("MediaPipe helper layout incomplete source=\(serverInfo.source) dir=\(serverInfo.dir) missing=\(missingText)")
            return false
        }
        return true
    }

    private func logMissingReleaseServerLayout() {
        let bundledScript = bundledPythonServerScript ?? "Contents/Resources/python_server/pose_server.py"
        let bundledDir = ((bundledScript as NSString).deletingLastPathComponent as NSString).standardizingPath
        let expected = requiredServerRelativePaths
            .map { (bundledDir as NSString).appendingPathComponent($0) }
            .joined(separator: ", ")
        log("Bundled MediaPipe helper not found. Release build expects: \(expected)")
    }

    /// Find the pose_server.py script and its directory.
    /// Public release should prefer bundled resources first; dev fallbacks stay DEBUG-only.
    private func findServerScript() -> ServerScriptLocation? {
        if let bundledScript = bundledPythonServerScript {
            let resolved = (bundledScript as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                let dir = (resolved as NSString).deletingLastPathComponent
                return ServerScriptLocation(script: resolved, dir: dir, source: "bundled", bundled: true)
            }
        }

        #if DEBUG
        let devCandidates = [
            ServerScriptLocation(
                script: (NSHomeDirectory() + "/.pt_turtle/server/pose_server.py" as NSString).standardizingPath,
                dir: (NSHomeDirectory() + "/.pt_turtle/server" as NSString).standardizingPath,
                source: "user-local",
                bundled: false
            ),
            ServerScriptLocation(
                script: (Bundle.main.bundlePath + "/../python_server/pose_server.py" as NSString).standardizingPath,
                dir: ((Bundle.main.bundlePath + "/../python_server") as NSString).standardizingPath,
                source: "bundle-relative-dev",
                bundled: false
            ),
            ServerScriptLocation(
                script: ("./python_server/pose_server.py" as NSString).standardizingPath,
                dir: ("./python_server" as NSString).standardizingPath,
                source: "cwd-dev",
                bundled: false
            ),
        ]

        for candidate in devCandidates where FileManager.default.fileExists(atPath: candidate.script) {
            return candidate
        }
        #endif

        return nil
    }

    /// Find python3 executable.
    /// Public release should prefer a bundled runtime; DEBUG builds may fall back to local dev runtimes.
    private func findPython(serverDir: String, preferBundled: Bool) -> PythonLaunch? {
        if preferBundled, let bundledLayout = resolveBundledPythonLayout() {
            return PythonLaunch(executable: bundledLayout.executable, argumentsPrefix: [], source: bundledLayout.source)
        }

        #if DEBUG
        let venvPython = (serverDir as NSString).appendingPathComponent(".venv/bin/python3")
        if FileManager.default.fileExists(atPath: venvPython) {
            return PythonLaunch(executable: venvPython, argumentsPrefix: [], source: "local-venv")
        }

        return PythonLaunch(executable: "/usr/bin/env", argumentsPrefix: ["python3"], source: "system-python3")
        #else
        return nil
        #endif
    }

    /// Start the Python MediaPipe server process.
    private func startPythonServer() -> Bool {
        guard pythonProcess == nil || pythonProcess?.isRunning != true else {
            return true
        }

        guard let serverInfo = findServerScript() else {
            #if DEBUG
            log("Cannot find pose_server.py in bundled or development locations")
            #else
            logMissingReleaseServerLayout()
            #endif
            return false
        }

        guard validateServerLayout(serverInfo) else {
            return false
        }

        let bundledLayout = serverInfo.bundled ? resolveBundledPythonLayout() : nil
        #if !DEBUG
        if serverInfo.bundled && bundledLayout == nil {
            let packageCandidates = releasePackageCandidates().joined(separator: ", ")
            log("Bundled Python runtime/package layout not usable for MediaPipe helper. Checked: \(packageCandidates)")
            return false
        }
        #endif

        guard let pythonLaunch = findPython(serverDir: serverInfo.dir, preferBundled: serverInfo.bundled) else {
            let runtimeCandidates = releaseRuntimeCandidates(serverDir: serverInfo.dir).joined(separator: ", ")
            log("No usable Python runtime for pose server source=\(serverInfo.source). Checked: \(runtimeCandidates)")
            return false
        }
        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: pythonLaunch.executable)
        process.arguments = pythonLaunch.argumentsPrefix + [serverInfo.script]
        process.currentDirectoryURL = URL(fileURLWithPath: serverInfo.dir, isDirectory: true)

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        if let bundledLayout {
            environment["PYTHONHOME"] = bundledLayout.pythonHome
            if let pythonPath = joinedEnvironmentPath(existing: environment["PYTHONPATH"], prepending: bundledLayout.pythonPathEntries) {
                environment["PYTHONPATH"] = pythonPath
            }
            if let dylibPath = joinedEnvironmentPath(existing: environment["DYLD_LIBRARY_PATH"], prepending: bundledLayout.dylibDirectories) {
                environment["DYLD_LIBRARY_PATH"] = dylibPath
            }
            if let dylibFallbackPath = joinedEnvironmentPath(existing: environment["DYLD_FALLBACK_LIBRARY_PATH"], prepending: bundledLayout.dylibDirectories) {
                environment["DYLD_FALLBACK_LIBRARY_PATH"] = dylibFallbackPath
            }
        }
        process.environment = environment

        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
            pythonProcess = process
            if let bundledLayout {
                log(
                    "Started Python server (PID \(process.processIdentifier)) source=\(serverInfo.source) runtime=\(pythonLaunch.source) " +
                        "pythonHome=\(bundledLayout.pythonHome) pythonPathCount=\(bundledLayout.pythonPathEntries.count) " +
                        "dylibDirCount=\(bundledLayout.dylibDirectories.count)"
                )
            } else {
                log("Started Python server (PID \(process.processIdentifier)) source=\(serverInfo.source) runtime=\(pythonLaunch.source)")
            }
            // Give server time to start listening
            Thread.sleep(forTimeInterval: 1.5)
            if !process.isRunning {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let stderrText, !stderrText.isEmpty {
                    log("Python server exited during startup source=\(serverInfo.source) runtime=\(pythonLaunch.source) stderr=\(stderrText)")
                } else if let reason = process.terminationReason as Process.TerminationReason? {
                    log("Python server exited during startup source=\(serverInfo.source) runtime=\(pythonLaunch.source) status=\(process.terminationStatus) reason=\(reason.rawValue)")
                } else {
                    log("Python server exited during startup source=\(serverInfo.source) runtime=\(pythonLaunch.source)")
                }
                pythonProcess = nil
                return false
            }
            return true
        } catch {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stderrText, !stderrText.isEmpty {
                log("Failed to start Python server source=\(serverInfo.source) runtime=\(pythonLaunch.source): \(error) stderr=\(stderrText)")
            } else {
                log("Failed to start Python server source=\(serverInfo.source) runtime=\(pythonLaunch.source): \(error)")
            }
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
        // Close any existing socket before reconnecting
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
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
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _isConnected = true
        log("Connected to pose server")
        return true
    }

    func connectAsync() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.connect())
            }
        }
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
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
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
    private func disconnectOnQueue() {
        _isConnected = false
        lastReliableCVA = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        fileHandle = nil
    }

    func disconnect() {
        if isOnQueue {
            disconnectOnQueue()
        } else {
            queue.sync {
                self.disconnectOnQueue()
            }
        }
    }

    /// Disconnect and stop the Python process.
    private func shutdownOnQueue() {
        // Try sending shutdown message
        if _isConnected {
            _ = sendRaw(data: "SHUTDOWN".data(using: .utf8)!)
        }
        disconnectOnQueue()
        stopPythonServer()
    }

    func shutdown() {
        if isOnQueue {
            shutdownOnQueue()
        } else {
            queue.sync {
                self.shutdownOnQueue()
            }
        }
    }

    func shutdownAsync() {
        queue.async {
            self.shutdownOnQueue()
        }
    }

    // MARK: - Frame Communication

    /// Send a CGImage frame and receive MediaPipeResult.
    func sendFrame(_ image: CGImage) -> MediaPipeResult? {
        guard _isConnected, socketFD >= 0 else { return nil }

        // Convert CGImage to JPEG data
        guard let jpegData = jpegData(from: image, quality: 0.7) else { return nil }

        // Send length-prefixed JPEG
        guard sendRaw(data: jpegData) else {
            disconnect()
            return nil
        }

        // Receive length-prefixed JSON response
        guard let responseData = receiveRaw() else {
            disconnect()
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

    func sendFrameAsync(_ image: CGImage) async -> MediaPipeResult? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.sendFrame(image))
            }
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
        logger.log("\(msg, privacy: .public)")
        #if DEBUG
        let line = "\(Date()): [MediaPipeClient] \(msg)\n"
        DebugLogWriter.append(line)
        #endif
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
