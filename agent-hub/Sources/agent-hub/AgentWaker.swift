import ChildProcess
import Foundation

// Starts a 5-hour usage window for each agent with one short request, outside any project and without a saved session.
enum AgentWaker {
    private static let greeting = "Hi"
    private static let executableDirectories = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]

    private static var workingDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/agent-hub/wake-up")
    }

    // Returns one line per agent that could not be woken.
    static func wakeUpAgents() -> [String] {
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        var claudeFailure: String?
        var codexFailure: String?
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            claudeFailure = wake("Claude Code", "claude", ["-p", "--no-session-persistence", "--model", "haiku", greeting])
        }
        DispatchQueue.global().async(group: group) {
            codexFailure = wake("Codex", "codex", ["exec", "--ephemeral", "--skip-git-repo-check", "-c", "model_reasoning_effort=\"low\"", greeting])
        }
        group.wait()

        AgentUsageReader.forgetCache()
        return [claudeFailure, codexFailure].compactMap { $0 }
    }

    private static func wake(_ agentName: String, _ executableName: String, _ arguments: [String]) -> String? {
        guard let executable = findExecutable(executableName) else { return "\(agentName): '\(executableName)' not found" }
        guard let result = ChildProcess.run(executable, arguments, workingDirectory: workingDirectory.path) else { return "\(agentName): could not start" }
        guard result.isSuccess else {
            let reason = String(decoding: result.errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(agentName): \(reason.split(separator: "\n").last.map(String.init) ?? "exited with \(result.exitStatus)")"
        }
        return nil
    }

    private static func findExecutable(_ name: String) -> String? {
        executableDirectories
            .map { ($0 as NSString).expandingTildeInPath + "/" + name }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
