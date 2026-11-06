import Darwin
import Foundation

struct CodexSessionRecord {
    let pid: Int32
    let thread: CodexThread
}

enum CodexSessionReader {
    // The daemon does not say which terminal process shows which thread, so a `codex resume <id>` argument pairs them
    // exactly and the rest are paired by working directory, oldest process with oldest thread.
    static func readLiveSessions(processTable: ProcessTable) -> [CodexSessionRecord] {
        guard processTable.codexArgumentsByPid.isEmpty == false, let client = CodexAppServerClient.connect() else { return [] }
        var unpairedThreads = client.listLoadedThreads().filter { $0.isSubagent == false }

        var records: [CodexSessionRecord] = []
        var unpairedPids: [Int32] = []
        for (pid, arguments) in processTable.codexArgumentsByPid.sorted(by: { $0.key < $1.key }) {
            if let index = unpairedThreads.firstIndex(where: { arguments.contains($0.id) }) {
                records.append(CodexSessionRecord(pid: pid, thread: unpairedThreads.remove(at: index)))
            }
            else {
                unpairedPids.append(pid)
            }
        }

        unpairedThreads.sort { $0.createdAt < $1.createdAt }
        for pid in unpairedPids {
            guard let cwd = readWorkingDirectory(of: pid),
                  let index = unpairedThreads.firstIndex(where: { ProcessTable.normalize($0.cwd) == cwd }) else { continue }
            records.append(CodexSessionRecord(pid: pid, thread: unpairedThreads.remove(at: index)))
        }
        return records
    }

    static func rename(_ threadId: String, to name: String) -> Bool {
        CodexAppServerClient.connect()?.setThreadName(threadId, to: name) ?? false
    }

    static func readLastMessage(of thread: CodexThread) -> AgentLastMessage? {
        guard let rolloutPath = thread.rolloutPath else { return nil }
        return TranscriptUtils.findLastMessage(in: URL(fileURLWithPath: rolloutPath), extractText: extractAssistantText)
    }

    private static func extractAssistantText(_ line: Substring) -> String? {
        guard line.contains("\"assistant\""),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              payload["role"] as? String == "assistant",
              let content = payload["content"] as? [[String: Any]] else { return nil }

        return content.compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }.last
    }

    private static func readWorkingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        return path.isEmpty ? nil : ProcessTable.normalize(path)
    }
}
