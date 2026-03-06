import Foundation

enum DebugLogWriter {
    private static let logURL = URL(fileURLWithPath: "/tmp/turtle_cvadebug.log")
    private static let queue = DispatchQueue(label: "pt_turtle.debug_log", qos: .utility)

    static func append(_ text: String) {
        #if DEBUG
        guard let data = text.data(using: .utf8) else { return }
        queue.async {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
        #endif
    }
}
