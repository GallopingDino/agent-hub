import Darwin
import Foundation

// The tasks an agent reported for its session: codes as its tracker writes them, or links. Kept under /tmp, the one place a
// sandboxed Codex command may write outside its project.
enum TaskStore {
    private static let sessionVariableByAgentProcess = [
        "claude": "CLAUDE_CODE_SESSION_ID",
        "codex": "CODEX_THREAD_ID",
        "agy": "ANTIGRAVITY_CONVERSATION_ID",
    ]

    private static var directory: URL {
        URL(fileURLWithPath: "/tmp/agent-hub-\(getuid())/tasks", isDirectory: true)
    }

    // Each agent hands the commands it runs its session id. An agent started from inside another one inherits the outer
    // agent's variable too, so the nearest agent among the parent processes decides which variable counts.
    static func findCallingSessionId() -> String? {
        let environment = ProcessInfo.processInfo.environment
        var pid = getppid()
        while pid > 1 {
            if let name = readCommandName(of: pid), let variable = sessionVariableByAgentProcess[name], let sessionId = environment[variable], sessionId.isEmpty == false {
                return sessionId
            }
            guard let parentPid = readParentPid(of: pid) else { break }
            pid = parentPid
        }
        return nil
    }

    private static func readParentPid(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    // The name the process was started by: Claude Code's executable file is named after its version.
    private static func readCommandName(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // argc, the executable path, padding zeros, then argv[0].
        var offset = MemoryLayout<Int32>.size
        while offset < size, buffer[offset] != 0 { offset += 1 }
        while offset < size, buffer[offset] == 0 { offset += 1 }
        let start = offset
        while offset < size, buffer[offset] != 0 { offset += 1 }
        guard offset > start else { return nil }
        return (String(decoding: buffer[start..<offset], as: UTF8.self) as NSString).lastPathComponent
    }

    // "ABC-123=https://…" names both; a lone argument is a link when it has a scheme, otherwise a code.
    static func parse(_ argument: String) -> TaskReference {
        if let separator = argument.firstIndex(of: "="), argument[..<separator].contains("://") == false {
            let code = String(argument[..<separator])
            let link = String(argument[argument.index(after: separator)...])
            return TaskReference(code: code.isEmpty ? nil : code, link: link.isEmpty ? nil : link)
        }
        return argument.contains("://") ? TaskReference(code: nil, link: argument) : TaskReference(code: argument, link: nil)
    }

    static func save(_ tasks: [TaskReference], forSession sessionId: String) -> Bool {
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

    static func read(forSession sessionId: String) -> [TaskReference] {
        guard let data = try? Data(contentsOf: fileUrl(of: sessionId)) else { return [] }
        return (try? JSONDecoder().decode([TaskReference].self, from: data)) ?? []
    }

    private static func fileUrl(of sessionId: String) -> URL {
        let safeName = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safeName).json")
    }
}
