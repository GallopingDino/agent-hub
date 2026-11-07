import Foundation

// The tasks an agent reported for its session: codes as its tracker writes them, or links. Kept under /tmp, the one place a
// sandboxed Codex command may write outside its project.
enum TaskStore {
    private static var directory: URL {
        URL(fileURLWithPath: "/tmp/agent-hub-\(getuid())/tasks", isDirectory: true)
    }

    // Claude Code and Codex hand every command they run the id of the session it belongs to.
    static func findCallingSessionId() -> String? {
        let environment = ProcessInfo.processInfo.environment
        return [environment["CLAUDE_CODE_SESSION_ID"], environment["CODEX_THREAD_ID"]].compactMap { $0 }.first { $0.isEmpty == false }
    }

    static func save(_ tasks: [String], forSession sessionId: String) -> Bool {
        let file = fileUrl(of: sessionId)
        guard tasks.isEmpty == false else {
            try? FileManager.default.removeItem(at: file)
            return true
        }
        guard let data = try? JSONEncoder().encode(tasks) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return true
        }
        catch {
            return false
        }
    }

    static func read(forSession sessionId: String) -> [String] {
        guard let data = try? Data(contentsOf: fileUrl(of: sessionId)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func fileUrl(of sessionId: String) -> URL {
        let safeName = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safeName).json")
    }
}
