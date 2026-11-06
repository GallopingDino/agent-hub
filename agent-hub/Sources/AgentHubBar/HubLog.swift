import Foundation

enum HubLog {
    private static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/agent-hub.log")
    }

    static func write(_ message: String) {
        let line = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        }
        else {
            try? line.write(to: file)
        }
    }
}
