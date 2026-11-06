import Foundation

struct ClaudeSessionRecord: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String?
    let status: String?
    let waitingFor: String?
    let statusUpdatedAt: Double?
}

enum ClaudeSessionReader {
    private static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    static func readLiveSessions() -> [ClaudeSessionRecord] {
        let sessionsDirectory = claudeDirectory.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(ClaudeSessionRecord.self, from: Data(contentsOf: $0)) }
            .filter { isProcessAlive($0.pid) }
    }

    static func readName(ofProcess pid: Int32) -> String? {
        let file = claudeDirectory.appendingPathComponent("sessions/\(pid).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONDecoder().decode(ClaudeSessionRecord.self, from: data))?.name
    }

    static func findTranscript(of session: ClaudeSessionRecord) -> URL {
        let escapedDirectory = session.cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        return claudeDirectory
            .appendingPathComponent("projects")
            .appendingPathComponent(escapedDirectory)
            .appendingPathComponent(session.sessionId + ".jsonl")
    }

    static func readLastMessage(of session: ClaudeSessionRecord) -> AgentLastMessage? {
        TranscriptUtils.findLastMessage(in: findTranscript(of: session), extractText: extractAssistantText)
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func extractAssistantText(_ line: Substring) -> String? {
        guard line.contains("\"assistant\""),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return nil }

        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.last
    }
}
