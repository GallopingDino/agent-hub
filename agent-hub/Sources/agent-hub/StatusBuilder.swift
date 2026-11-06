import Foundation

enum StatusBuilder {
    private static let maxParallelJobs = 4
    private static let previewLength = 140

    static func build(config: HubConfig) -> HubStatus {
        let clonePaths = config.findClonePaths()
        let processTable = ProcessTable()
        let tabs = AgentTabsClient.listTabs()
        let records = ClaudeSessionReader.readLiveSessions()

        var artifactCache = ArtifactLinkCache()
        let artifactUrls = records.map { artifactCache.findLatestArtifactUrl(of: $0) }
        artifactCache.save()

        let sessions = parallelMap(Array(zip(records, artifactUrls))) { record, artifactUrl in
            buildSession(record, artifactUrl: artifactUrl, clonePaths: clonePaths, tabs: tabs ?? [], processTable: processTable, config: config)
        }
        .sorted { ($0.state.sortOrder, $0.idleSeconds) < ($1.state.sortOrder, $1.idleSeconds) }

        var worktreeCache = WorktreeChangesCache()
        let clones = clonePaths.map { path in
            let sessionCount = sessions.filter { $0.clonePath == path }.count
            let stagedCount = GitInspector.countStagedFiles(in: path)
            let isFreeCandidate = sessionCount == 0 && stagedCount == 0
            let changedCount = isFreeCandidate ? worktreeCache.countChangedFiles(in: path) : nil
            return CloneState(
                name: (path as NSString).lastPathComponent,
                path: path,
                branch: GitInspector.readBranch(of: path),
                stagedCount: stagedCount,
                changedCount: changedCount,
                isUnityOpen: processTable.unityProjectPaths.contains(path),
                sessionCount: sessionCount,
                isFree: isFreeCandidate && changedCount == 0
            )
        }
        worktreeCache.save()

        return HubStatus(generatedAt: Date(), isAgentTabsAvailable: tabs != nil, sessions: sessions, clones: clones)
    }

    private static func buildSession(_ record: ClaudeSessionRecord, artifactUrl: String?, clonePaths: [String], tabs: [RiderTerminalTab], processTable: ProcessTable, config: HubConfig) -> AgentSession {
        let workingDirectory = ProcessTable.normalize(record.cwd)
        let clonePath = findClone(containing: workingDirectory, clonePaths: clonePaths)
        let lastMessage = ClaudeSessionReader.readLastMessage(of: record)
        let reviewFiles = collectStillChangedFiles(lastMessage?.reportedFiles ?? [], baseDirectory: clonePath ?? workingDirectory)
        let tab = tabs.first { tab in tab.shellPid.map { processTable.isDescendant(record.pid, of: $0) } ?? false }

        let idleSeconds = record.statusUpdatedAt.map { max(0, Int(Date().timeIntervalSince1970 - $0 / 1000)) } ?? 0
        let state = classify(status: record.status, idleSeconds: idleSeconds, hasReviewFiles: reviewFiles.isEmpty == false, config: config)

        return AgentSession(
            sessionId: record.sessionId,
            pid: record.pid,
            name: record.name,
            workingDirectory: workingDirectory,
            clonePath: clonePath,
            cloneName: clonePath.map { ($0 as NSString).lastPathComponent },
            state: state,
            waitingFor: record.status == "waiting" ? record.waitingFor : nil,
            idleSeconds: idleSeconds,
            lastMessagePreview: lastMessage.map { makePreview($0.text) },
            reviewFiles: reviewFiles,
            artifactUrl: artifactUrl,
            riderProject: tab?.project,
            hasTerminalTab: tab != nil
        )
    }

    private static func classify(status: String?, idleSeconds: Int, hasReviewFiles: Bool, config: HubConfig) -> AgentState {
        switch status {
        case "busy":
            return .working
        case "waiting":
            return .waiting
        default:
            if hasReviewFiles { return .review }
            return Double(idleSeconds) > config.staleAfterHours * 3600 ? .stale : .idle
        }
    }

    private static func findClone(containing path: String, clonePaths: [String]) -> String? {
        clonePaths
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
    }

    private static func collectStillChangedFiles(_ reportedFiles: [String], baseDirectory: String) -> [String] {
        let absolutePaths = reportedFiles.map { $0.hasPrefix("/") ? ProcessTable.normalize($0) : ProcessTable.normalize(baseDirectory + "/" + $0) }

        var filesByRepository: [String: [String]] = [:]
        for path in absolutePaths {
            if let repository = findRepositoryRoot(of: path) {
                filesByRepository[repository, default: []].append(path)
            }
        }

        let changed = filesByRepository.flatMap { repository, files in GitInspector.filterChangedFiles(in: repository, absolutePaths: files) }
        return absolutePaths.filter { changed.contains($0) }
    }

    private static func findRepositoryRoot(of filePath: String) -> String? {
        var directory = (filePath as NSString).deletingLastPathComponent
        while directory.count > 1 {
            if GitInspector.isRepository(directory) {
                return directory
            }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func makePreview(_ text: String) -> String {
        let firstLine = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false } ?? ""
        let plain = firstLine.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        return plain.count > previewLength ? String(plain.prefix(previewLength)) + "…" : plain
    }

    private static func parallelMap<T, R>(_ items: [T], _ transform: (T) -> R) -> [R] {
        var results = [R?](repeating: nil, count: items.count)
        let lock = NSLock()
        let slots = DispatchSemaphore(value: maxParallelJobs)
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            slots.wait()
            let value = transform(items[index])
            slots.signal()
            lock.lock()
            results[index] = value
            lock.unlock()
        }
        return results.map { $0! }
    }
}
