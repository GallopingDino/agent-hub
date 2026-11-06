import Foundation

struct ProcessTable {
    private let parentByPid: [Int32: Int32]

    let unityEditorPidByProject: [String: Int32]

    init() {
        var parents: [Int32: Int32] = [:]
        var unityEditors: [String: Int32] = [:]
        let projectPathPattern = try! NSRegularExpression(pattern: "-projectpath\\s+(\\S+)", options: .caseInsensitive)

        let output = ShellCommand.run("/bin/ps", ["-axo", "pid=,ppid=,command="]) ?? ""
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int32(parts[0]), let parentPid = Int32(parts[1]) else { continue }
            parents[pid] = parentPid

            guard parts.count == 3, parts[2].contains("Unity.app/Contents/MacOS/Unity") else { continue }
            let command = String(parts[2])
            if command.localizedCaseInsensitiveContains("-batchmode") { continue }

            let range = NSRange(command.startIndex..., in: command)
            if let match = projectPathPattern.firstMatch(in: command, range: range), let pathRange = Range(match.range(at: 1), in: command) {
                unityEditors[Self.normalize(String(command[pathRange]))] = pid
            }
        }

        parentByPid = parents
        unityEditorPidByProject = unityEditors
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

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
