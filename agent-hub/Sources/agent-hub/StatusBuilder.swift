import Foundation

private enum SessionSource {
    case claude(ClaudeSessionRecord, artifactUrl: String?)
    case codex(CodexSessionRecord)
}

// What every agent reports about one session, before it is placed into a clone, a Rider tab and a state.
private struct ObservedSession {
    let agent: AgentKind
    let pid: Int32
    let sessionId: String
    let workingDirectory: String
    let name: String?
    let status: String?
    let waitingFor: String?
    let idleSeconds: Int
    let lastMessage: AgentLastMessage?
    let artifactUrl: String?
}

enum StatusBuilder {
    private static let maxParallelJobs = 4
    private static let previewLength = 140
    private static let codexFallbackNameLength = 40

    static func build(config: HubConfig) -> HubStatus {
        let clonePaths = config.findClonePaths()
        let processTable = ProcessTable()
        let tabs = AgentTabsClient.listTabs()
        let sessions = buildSessions(clonePaths: clonePaths, processTable: processTable, tabs: tabs ?? [], config: config)
        let clones = buildClones(clonePaths, sessions: sessions, processTable: processTable)
        return HubStatus(generatedAt: Date(), isAgentTabsAvailable: tabs != nil, sessions: sessions, clones: clones)
    }

    // Skips the per-clone git checks, which take most of the time of build(). The Rider plugin itself asks without
    // tab lookup: that lookup calls back into the plugin and would wait on the thread that is waiting for this answer.
    static func buildSessions(config: HubConfig, isLookingUpRiderTabs: Bool = true) -> [AgentSession] {
        let tabs = isLookingUpRiderTabs ? AgentTabsClient.listTabs() ?? [] : []
        return buildSessions(clonePaths: config.findClonePaths(), processTable: ProcessTable(), tabs: tabs, config: config)
    }

    private static func buildSessions(clonePaths: [String], processTable: ProcessTable, tabs: [RiderTerminalTab], config: HubConfig) -> [AgentSession] {
        let claudeRecords = ClaudeSessionReader.readLiveSessions()
        var artifactCache = ArtifactLinkCache()
        let claudeSources = claudeRecords.map { SessionSource.claude($0, artifactUrl: artifactCache.findLatestArtifactUrl(of: $0)) }
        artifactCache.save()

        let codexSources = CodexSessionReader.readLiveSessions(processTable: processTable).map(SessionSource.codex)

        return parallelMap(claudeSources + codexSources) { source in
            buildSession(observe(source), clonePaths: clonePaths, tabs: tabs, processTable: processTable, config: config)
        }
        .sorted { ($0.state.sortOrder, $0.idleSeconds) < ($1.state.sortOrder, $1.idleSeconds) }
    }

    private static func buildClones(_ clonePaths: [String], sessions: [AgentSession], processTable: ProcessTable) -> [CloneState] {
        let openIdeProjects = IdeIntegrations.readOpenProjectDirectories()
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
                unityPid: processTable.unityEditorPidByProject[path],
                isOpenInRider: openIdeProjects.contains(path),
                sessionCount: sessionCount,
                isFree: isFreeCandidate && changedCount == 0
            )
        }
        worktreeCache.save()
        return clones
    }

    private static func observe(_ source: SessionSource) -> ObservedSession {
        switch source {
        case let .claude(record, artifactUrl):
            return ObservedSession(
                agent: .claude,
                pid: record.pid,
                sessionId: record.sessionId,
                workingDirectory: record.cwd,
                name: record.name,
                status: record.status,
                waitingFor: record.waitingFor,
                idleSeconds: record.statusUpdatedAt.map { max(0, Int(Date().timeIntervalSince1970 - $0 / 1000)) } ?? 0,
                lastMessage: ClaudeSessionReader.readLastMessage(of: record),
                artifactUrl: artifactUrl
            )
        case let .codex(record):
            let thread = record.thread
            let (status, waitingFor) = translateCodexStatus(thread)
            return ObservedSession(
                agent: .codex,
                pid: record.pid,
                sessionId: thread.id,
                workingDirectory: thread.cwd,
                name: thread.name ?? thread.preview.flatMap(makeCodexFallbackName),
                status: status,
                waitingFor: waitingFor,
                idleSeconds: max(0, Int(Date().timeIntervalSince1970 - thread.updatedAt)),
                lastMessage: CodexSessionReader.readLastMessage(of: thread),
                artifactUrl: nil
            )
        }
    }

    // Maps Codex thread status onto the Claude Code status words that classify() understands.
    private static func translateCodexStatus(_ thread: CodexThread) -> (status: String?, waitingFor: String?) {
        switch thread.statusType {
        case "active":
            if thread.activeFlags.contains("waitingOnApproval") { return ("waiting", "approval") }
            if thread.activeFlags.contains("waitingOnUserInput") { return ("waiting", "input needed") }
            return ("busy", nil)
        case "systemError":
            return ("waiting", "error")
        default:
            return (nil, nil)
        }
    }

    private static func makeCodexFallbackName(_ preview: String) -> String? {
        let firstLine = preview.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard firstLine.isEmpty == false else { return nil }
        return firstLine.count > codexFallbackNameLength ? String(firstLine.prefix(codexFallbackNameLength)) + "…" : firstLine
    }

    private static func buildSession(_ observed: ObservedSession, clonePaths: [String], tabs: [RiderTerminalTab], processTable: ProcessTable, config: HubConfig) -> AgentSession {
        let workingDirectory = ProcessTable.normalize(observed.workingDirectory)
        let clonePath = findClone(containing: workingDirectory, clonePaths: clonePaths)
        let reviewFiles = collectStillChangedFiles(observed.lastMessage?.reportedFiles ?? [], baseDirectory: clonePath ?? workingDirectory)
        let tab = tabs.first { tab in tab.shellPid.map { processTable.isDescendant(observed.pid, of: $0) } ?? false }
        let state = classify(status: observed.status, idleSeconds: observed.idleSeconds, hasReviewFiles: reviewFiles.isEmpty == false, config: config)

        return AgentSession(
            sessionId: observed.sessionId,
            pid: observed.pid,
            agent: observed.agent,
            name: observed.name,
            workingDirectory: workingDirectory,
            clonePath: clonePath,
            cloneName: clonePath.map { ($0 as NSString).lastPathComponent },
            state: state,
            waitingFor: observed.status == "waiting" ? observed.waitingFor : nil,
            idleSeconds: observed.idleSeconds,
            lastMessagePreview: observed.lastMessage.map { makePreview($0.text) },
            reviewFiles: reviewFiles,
            artifactUrl: observed.artifactUrl,
            riderProject: tab?.project,
            hasTerminalTab: tab != nil,
            unityPid: clonePath.flatMap { processTable.unityEditorPidByProject[$0] }
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
        var seenPaths: Set<String> = []
        let absolutePaths = reportedFiles
            .map { $0.hasPrefix("/") ? ProcessTable.normalize($0) : ProcessTable.normalize(baseDirectory + "/" + $0) }
            .filter { seenPaths.insert($0).inserted }

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
        let plain = firstLine
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>-• ").union(.whitespaces))
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
