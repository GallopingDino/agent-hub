import Foundation

struct ProcessTable {
    // Subcommands that never host an interactive session.
    private static let codexBackgroundCommands: Set<String> = [
        "app-server", "exec", "e", "mcp", "mcp-server", "review", "login", "logout", "sandbox", "debug", "apply", "a", "exec-server",
        "cloud", "completion", "features", "doctor", "update", "plugin", "queue", "archive", "delete", "unarchive", "migrate-rollouts",
        "migrate-nfs-db", "remote-control", "app", "agents", "help",
    ]

    private let parentByPid: [Int32: Int32]

    let unityEditorPidByProject: [String: Int32]
    // A process left behind by a closed terminal keeps running with no controlling terminal.
    let pidsWithoutTerminal: Set<Int32>
    let codexArgumentsByPid: [Int32: [String]]

    init() {
        var parents: [Int32: Int32] = [:]
        var unityEditors: [String: Int32] = [:]
        var codexSessions: [Int32: [String]] = [:]
        var withoutTerminal: Set<Int32> = []
        let projectPathPattern = try! NSRegularExpression(pattern: "-projectpath\\s+(\\S+)", options: .caseInsensitive)

        let output = ShellCommand.run("/bin/ps", ["-axo", "pid=,ppid=,tty=,command="]) ?? ""
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count >= 3, let pid = Int32(fields[0]), let parentPid = Int32(fields[1]) else { continue }
            parents[pid] = parentPid
            if fields[2] == "??" {
                withoutTerminal.insert(pid)
            }
            guard fields.count == 4 else { continue }
            let command = fields[3]

            if let arguments = Self.parseCodexSessionArguments(command) {
                codexSessions[pid] = arguments
            }

            guard command.contains("Unity.app/Contents/MacOS/Unity") else { continue }
            let unityCommand = String(command)
            if unityCommand.localizedCaseInsensitiveContains("-batchmode") { continue }

            let range = NSRange(unityCommand.startIndex..., in: unityCommand)
            if let match = projectPathPattern.firstMatch(in: unityCommand, range: range), let pathRange = Range(match.range(at: 1), in: unityCommand) {
                unityEditors[Self.normalize(String(unityCommand[pathRange]))] = pid
            }
        }

        parentByPid = parents
        unityEditorPidByProject = unityEditors
        pidsWithoutTerminal = withoutTerminal
        codexArgumentsByPid = codexSessions
    }

    func isDescendant(_ pid: Int32, of ancestor: Int32) -> Bool {
        var current: Int32? = pid
        var steps = 0
        while let value = current, steps < 64 {
            if value == ancestor { return true }
            current = parentByPid[value]
            steps += 1
        }
        return false
    }

    private static func parseCodexSessionArguments(_ command: Substring) -> [String]? {
        let words = command.split(separator: " ").map(String.init)
        guard let executable = words.first, (executable as NSString).lastPathComponent == "codex" else { return nil }
        let arguments = Array(words.dropFirst())
        if let subcommand = arguments.first, codexBackgroundCommands.contains(subcommand) {
            return nil
        }
        return arguments
    }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
