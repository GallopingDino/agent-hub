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

struct ClaudeLastMessage {
    let text: String
    let reportedFiles: [String]
}

enum ClaudeSessionReader {
    private static let changedFilesMarker = "Изменённые файлы:"
    private static let tailWindows = [512 * 1024, 4 * 1024 * 1024]

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

    static func readLastMessage(of session: ClaudeSessionRecord) -> ClaudeLastMessage? {
        let transcript = findTranscript(of: session)

        for window in tailWindows {
            guard let tail = readTail(of: transcript, byteCount: window) else { return nil }
            if let text = findLastAssistantText(in: tail.text) {
                return ClaudeLastMessage(text: text, reportedFiles: parseReportedFiles(text))
            }
            if tail.isWholeFile {
                return nil
            }
        }
        return nil
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func readTail(of file: URL, byteCount: Int) -> (text: String, isWholeFile: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(byteCount) ? size - UInt64(byteCount) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return (String(decoding: data, as: UTF8.self), offset == 0)
    }

    private static func findLastAssistantText(in jsonLines: String) -> String? {
        for line in jsonLines.split(separator: "\n").reversed() {
            guard line.contains("\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }

            let texts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            if let text = texts.last, text.isEmpty == false {
                return text
            }
        }
        return nil
    }

    private static func parseReportedFiles(_ text: String) -> [String] {
        guard let markerRange = text.range(of: changedFilesMarker, options: .backwards) else { return [] }

        var files: [String] = []
        for rawLine in text[markerRange.upperBound...].split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            if line.hasPrefix("```") || line.isEmpty { continue }
            guard line.contains("/") || line.contains("."), line.contains(" ") == false else { break }
            files.append(stripLineSuffix(line))
        }
        return files
    }

    private static func stripLineSuffix(_ path: String) -> String {
        guard let colon = path.lastIndex(of: ":"),
              path[path.index(after: colon)...].allSatisfy(\.isNumber),
              path.index(after: colon) < path.endIndex else { return path }
        return String(path[..<colon])
    }
}
