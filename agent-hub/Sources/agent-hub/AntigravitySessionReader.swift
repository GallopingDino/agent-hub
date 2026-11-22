import Darwin
import Foundation

struct AntigravitySessionRecord {
    let pid: Int32
    let conversationId: String
    let cwd: String
    let title: String?
    let isRunning: Bool
    let updatedAt: Date?
}

// The Antigravity CLI (agy) keeps a summary of every conversation in one SQLite database and each conversation's
// steps in a database of its own. A running agy holds presence/<conversation id>.lock open, which tells which
// conversation a process shows.
enum AntigravitySessionReader {
    private static let busyStatuses: Set<String> = ["CASCADE_RUN_STATUS_RUNNING", "CASCADE_RUN_STATUS_BUSY", "CASCADE_RUN_STATUS_CANCELING"]
    private static let plannerResponseStepType = 15
    // CortexStep.planner_response.response
    private static let responseTextPath = [20, 1]
    private static let conversationIdPattern = try! NSRegularExpression(pattern: "^[0-9a-f-]{36}$")

    static var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity-cli")
    }

    static func readLiveSessions(processTable: ProcessTable) -> [AntigravitySessionRecord] {
        var processes: [(pid: Int32, conversationId: String, cwd: String)] = []
        for pid in processTable.antigravityPids {
            guard let cwd = ProcessTable.readWorkingDirectory(of: pid), cwd != AntigravityLanguageServer.helperDirectory.path,
                  let conversationId = findConversationId(ofProcess: pid) else { continue }
            processes.append((pid, conversationId, cwd))
        }
        guard processes.isEmpty == false else { return [] }

        let summaries = readSummaries(Set(processes.map(\.conversationId)))
        return processes.map { process in
            let summary = summaries[process.conversationId]
            return AntigravitySessionRecord(
                pid: process.pid,
                conversationId: process.conversationId,
                cwd: process.cwd,
                title: summary?.title,
                isRunning: summary.map { busyStatuses.contains($0.status) } ?? false,
                updatedAt: summary?.updatedAt
            )
        }
    }

    static func rename(_ conversationId: String, to name: String) -> Bool {
        let body: [String: Any] = ["cascadeId": conversationId, "annotations": ["title": name]]
        return AntigravityLanguageServer.withServer { $0.call("UpdateConversationAnnotations", body) } != nil
    }

    static func readLastMessage(ofConversation conversationId: String) -> AgentLastMessage? {
        let database = dataDirectory.appendingPathComponent("conversations/\(conversationId).db").path
        let sql = "select step_payload from steps where step_type = \(plannerResponseStepType) order by idx desc limit 1"
        guard let payload = SqliteReader.query(database, sql, access: .immutable).first?.first?.blob,
              let textData = ProtobufReader.findBytes(in: payload, path: responseTextPath) else { return nil }
        let text = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : AgentLastMessage(text: text)
    }

    private static func findConversationId(ofProcess pid: Int32) -> String? {
        let presenceDirectory = dataDirectory.appendingPathComponent("presence").path + "/"
        return listOpenFiles(of: pid)
            .first { $0.hasPrefix(presenceDirectory) && $0.hasSuffix(".lock") }
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
    }

    private static func listOpenFiles(of pid: Int32) -> [String] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride)
        let filledSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, bufferSize)
        guard filledSize > 0 else { return [] }

        return descriptors.prefix(Int(filledSize) / MemoryLayout<proc_fdinfo>.stride).compactMap { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return nil }
            return withUnsafeBytes(of: info.pvip.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
    }

    // agy keeps the summaries database locked, so the query runs on a copy that carries its write-ahead log along.
    private static func readSummaries(_ conversationIds: Set<String>) -> [String: (title: String?, status: String, updatedAt: Date?)] {
        let safeIds = conversationIds.filter { conversationIdPattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        guard safeIds.isEmpty == false, let copy = copySummariesDatabase() else { return [:] }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        let idList = safeIds.map { "'\($0)'" }.joined(separator: ",")
        let rows = SqliteReader.query(copy.path, "select conversation_id, title, status, last_modified_time from conversation_summaries where conversation_id in (\(idList))", access: .privateCopy)
        var summaries: [String: (title: String?, status: String, updatedAt: Date?)] = [:]
        for row in rows {
            guard let conversationId = row[0].text else { continue }
            let title = row[1].text.flatMap { $0.isEmpty ? nil : $0 }
            summaries[conversationId] = (title, row[2].text ?? "", row[3].text.flatMap(parseTimestamp))
        }
        return summaries
    }

    private static func copySummariesDatabase() -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("agent-hub-agy-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
        let name = "conversation_summaries.db"
        for suffix in ["", "-wal", "-shm"] {
            let source = dataDirectory.appendingPathComponent(name + suffix)
            try? FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name + suffix))
        }
        return directory.appendingPathComponent(name)
    }

    // "2026-11-22 10:02:51.936064+00:00"
    private static func parseTimestamp(_ text: String) -> Date? {
        let withoutFraction = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssxxx"
        return formatter.date(from: withoutFraction)
    }
}
