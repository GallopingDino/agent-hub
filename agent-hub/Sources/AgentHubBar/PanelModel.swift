import AppKit
import SwiftUI

enum SessionAction {
    case showTerminal
    case showUnity
    case openTask
    case openArtifact
}

enum CloseConfirmationOption: CaseIterable {
    case closeAll
    case tabOnly
    case cancel
}

@MainActor
final class PanelModel: ObservableObject {
    private static let openPanelRefreshSeconds: UInt64 = 10
    private static let closedPanelRefreshSeconds: UInt64 = 120
    private static let wakeUpUsageChecks = 6
    private static let wakeUpUsageCheckIntervalSeconds = 5
    private static let handyCheckIntervalSeconds = 5

    private let defaults = UserDefaults.standard

    // A link with {code} where a reported task code goes; a task reported as a link opens as it is.
    @Published var taskLinkTemplate: String {
        didSet { defaults.set(taskLinkTemplate, forKey: "taskLinkTemplate") }
    }
    @Published var isOpeningEditedFilesOnFocus: Bool {
        didSet { defaults.set(isOpeningEditedFilesOnFocus, forKey: "isOpeningEditedFilesOnFocus") }
    }
    @Published var groupingMode: GroupingMode {
        didSet { defaults.set(groupingMode.rawValue, forKey: "groupingMode") }
    }
    @Published private var groupOrderByMode: [String: [String]] {
        didSet { defaults.set(groupOrderByMode, forKey: "groupOrderByMode") }
    }
    @Published private(set) var status: PanelStatus?
    @Published private(set) var notice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var usage: [PanelAgentUsage] = []
    @Published private(set) var recentProjects: [PanelRecentProject] = []
    @Published var isInactiveExpanded = false
    @Published private(set) var selectedSessionId: String? {
        didSet { highlightedSessionAction = selectedSession.flatMap { findAvailableActions(for: $0).first } }
    }
    @Published private(set) var highlightedSessionAction: SessionAction?
    @Published private(set) var renamingSessionId: String?
    // The last agent of a project asks before its IDE window and Unity editor go too.
    @Published private(set) var confirmingCloseSessionId: String?
    @Published private(set) var highlightedCloseOption = CloseConfirmationOption.closeAll
    @Published private(set) var closingSessionIds: Set<String> = []
    @Published private(set) var isWakingUpAgents = false
    @Published private(set) var isClosingUnusedClones = false
    @Published private(set) var isHandyFrozen = false
    @Published private(set) var isRestartingHandy = false
    @Published private(set) var isResettingUsage = false
    // While a name is typed, the panel's letter shortcuts must not swallow the keys.
    @Published var isEditingName = false

    private var isPanelOpen = false
    private var refreshLoop: Task<Void, Never>?
    private var handyCheckLoop: Task<Void, Never>?
    private lazy var settingsMenu = SettingsMenuPresenter(model: self)

    var onLeavingForEditor: (() -> Void)?
    var onSettingsMenuToggled: (() -> Void)?

    var attentionCount: Int {
        status?.sessions.filter(\.isNeedingUser).count ?? 0
    }

    var isAnyAgentAsleep: Bool {
        usage.contains(where: \.isAsleep)
    }

    // Clones still open in Rider or Unity with no agent and no local changes.
    var unusedClones: [PanelClone] {
        status?.clones.filter { $0.isRunning && $0.isFree } ?? []
    }

    var isAnyAgentNearLimit: Bool {
        usage.contains(where: \.isNearLimit)
    }

    var selectedSession: PanelSession? {
        status?.sessions.first { $0.id == selectedSessionId }
    }

    var isSettingsMenuOpen: Bool {
        settingsMenu.isOpen
    }

    var groups: [SessionGroup] {
        SessionGrouping.makeGroups(status?.sessions ?? [], mode: groupingMode, savedOrder: readGroupOrder())
    }

    init() {
        isOpeningEditedFilesOnFocus = defaults.object(forKey: "isOpeningEditedFilesOnFocus") as? Bool ?? true
        taskLinkTemplate = defaults.string(forKey: "taskLinkTemplate") ?? ""
        groupingMode = GroupingMode(rawValue: defaults.string(forKey: "groupingMode") ?? "") ?? .status
        groupOrderByMode = defaults.dictionary(forKey: "groupOrderByMode") as? [String: [String]] ?? [:]
        startRefreshLoop()
        startHandyCheckLoop()
    }

    func panelDidOpen() {
        isPanelOpen = true
        startRefreshLoop()
    }

    func panelDidClose() {
        isPanelOpen = false
        deselectSession()
        startRefreshLoop()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        async let freshStatus = HubClient.fetchStatus()
        async let freshUsage = HubClient.fetchUsage(isBypassingCache: false)
        async let freshProjects = HubClient.fetchRecentProjects()
        if let fresh = await freshStatus {
            status = fresh
            closingSessionIds.formIntersection(fresh.sessions.map(\.id))
            if selectedSession == nil {
                deselectSession()
            }
        }
        if let fresh = await freshUsage {
            usage = fresh
        }
        if let fresh = await freshProjects {
            recentProjects = fresh
        }
        isRefreshing = false
    }

    // Without a point the menu opens at the mouse, as for a click on its button.
    func showSettingsMenu(at point: NSPoint? = nil) {
        settingsMenu.show(at: point)
    }

    func wakeUpAgents() {
        guard isWakingUpAgents == false else { return }
        isWakingUpAgents = true
        Task {
            showNotice(await HubClient.wakeUpAgents())
            await waitForAgentsToWake()
            isWakingUpAgents = false
        }
    }

    func closeUnusedClones(_ clones: [PanelClone]) {
        guard isClosingUnusedClones == false, clones.isEmpty == false else { return }
        isClosingUnusedClones = true
        Task {
            showNotice(await HubClient.closeClones(clones))
            await refresh()
            isClosingUnusedClones = false
        }
    }

    func restartHandy() {
        guard isRestartingHandy == false else { return }
        isRestartingHandy = true
        Task {
            showNotice(await HandyApp.restart())
            checkHandy()
            isRestartingHandy = false
        }
    }

    func resetUsage(of agentUsage: PanelAgentUsage) {
        guard isResettingUsage == false else { return }
        isResettingUsage = true
        Task {
            showNotice(await HubClient.resetUsage(of: agentUsage))
            if let fresh = await HubClient.fetchUsage(isBypassingCache: true) {
                usage = fresh
            }
            isResettingUsage = false
        }
    }

    // The usage APIs can take a few seconds to report the new window.
    private func waitForAgentsToWake() async {
        for attempt in 0..<Self.wakeUpUsageChecks {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Self.wakeUpUsageCheckIntervalSeconds))
            }
            if let fresh = await HubClient.fetchUsage(isBypassingCache: true) {
                usage = fresh
            }
            if isAnyAgentAsleep == false { return }
        }
    }

    func showAgent(_ session: PanelSession) {
        let isOpeningFiles = isOpeningEditedFilesOnFocus
        onLeavingForEditor?()
        Task { await HubClient.showAgent(session, isOpeningEditedFiles: isOpeningFiles) }
    }

    func toggleSelection(_ session: PanelSession) {
        confirmingCloseSessionId = nil
        selectedSessionId = selectedSessionId == session.id ? nil : session.id
    }

    // Arrow keys walk the rows as the panel shows them; from no selection, either arrow starts at the top.
    func selectAdjacentSession(by offset: Int) {
        let visible = groups.filter { $0.isInactive == false || isInactiveExpanded }.flatMap(\.sessions)
        guard visible.isEmpty == false else { return }
        let next: Int
        if let current = visible.firstIndex(where: { $0.id == selectedSessionId }) {
            next = min(max(current + offset, 0), visible.count - 1)
        }
        else {
            next = 0
        }
        confirmingCloseSessionId = nil
        selectedSessionId = visible[next].id
    }

    func deselectSession() {
        selectedSessionId = nil
        confirmingCloseSessionId = nil
    }

    func cancelClosing() {
        confirmingCloseSessionId = nil
    }

    // Left and Right walk the last-agent answers while asking, otherwise the selected row's buttons.
    func moveHighlight(by offset: Int) {
        guard let session = selectedSession else { return }
        if confirmingCloseSessionId == session.id {
            moveCloseHighlight(by: offset)
        }
        else {
            moveActionHighlight(in: findAvailableActions(for: session), by: offset)
        }
    }

    func findAvailableActions(for session: PanelSession) -> [SessionAction] {
        var actions: [SessionAction] = []
        if session.hasTerminalTab {
            actions.append(.showTerminal)
        }
        if session.unityPid != nil {
            actions.append(.showUnity)
        }
        if session.tasks.isEmpty == false {
            actions.append(.openTask)
        }
        if session.artifactUrl != nil {
            actions.append(.openArtifact)
        }
        return actions
    }

    func perform(_ action: SessionAction, for session: PanelSession) {
        switch action {
        case .showTerminal:
            showAgent(session)
        case .showUnity:
            if let unityPid = session.unityPid {
                showUnityEditor(pid: unityPid)
            }
        case .openTask:
            openTask(session)
        case .openArtifact:
            openArtifact(session)
        }
    }

    func finishRenameRequest() {
        renamingSessionId = nil
    }

    private func moveCloseHighlight(by offset: Int) {
        let options = CloseConfirmationOption.allCases
        guard let current = options.firstIndex(of: highlightedCloseOption) else { return }
        highlightedCloseOption = options[min(max(current + offset, 0), options.count - 1)]
    }

    private func moveActionHighlight(in actions: [SessionAction], by offset: Int) {
        guard actions.isEmpty == false else {
            highlightedSessionAction = nil
            return
        }
        guard let current = highlightedSessionAction.flatMap({ actions.firstIndex(of: $0) }) else {
            highlightedSessionAction = actions[0]
            return
        }
        highlightedSessionAction = actions[min(max(current + offset, 0), actions.count - 1)]
    }

    func isLastAgentInProject(_ session: PanelSession) -> Bool {
        let siblings = status?.sessions.filter { $0.hasTerminalTab && $0.projectName == session.projectName && closingSessionIds.contains($0.id) == false } ?? []
        return siblings.allSatisfy { $0.id == session.id }
    }

    func closeSelectedSession() {
        guard let session = selectedSession, session.hasTerminalTab, closingSessionIds.contains(session.id) == false, confirmingCloseSessionId == nil else { return }
        if isLastAgentInProject(session) {
            highlightedCloseOption = .closeAll
            confirmingCloseSessionId = session.id
        }
        else {
            close(session, isClosingProject: false)
        }
    }

    func showSelectedSessionTerminal() {
        guard let session = selectedSession, session.hasTerminalTab else { return }
        showAgent(session)
    }

    func startRenamingSelection() {
        guard let session = selectedSession, confirmingCloseSessionId == nil else { return }
        renamingSessionId = session.id
    }

    // Return answers the last-agent question or presses the highlighted button.
    func activateSelection() {
        guard let session = selectedSession, isSettingsMenuOpen == false else { return }
        if confirmingCloseSessionId == session.id {
            choose(highlightedCloseOption, for: session)
        }
        else if let action = highlightedSessionAction {
            perform(action, for: session)
        }
    }

    func choose(_ option: CloseConfirmationOption, for session: PanelSession) {
        switch option {
        case .closeAll:
            close(session, isClosingProject: true)
        case .tabOnly:
            close(session, isClosingProject: false)
        case .cancel:
            cancelClosing()
        }
    }

    func close(_ session: PanelSession, isClosingProject: Bool) {
        confirmingCloseSessionId = nil
        closingSessionIds.insert(session.id)
        if selectedSessionId == session.id {
            selectedSessionId = nil
        }
        Task {
            if let reason = await HubClient.close(session, isClosingProject: isClosingProject) {
                closingSessionIds.remove(session.id)
                showNotice(reason)
            }
            await refresh()
        }
    }

    func openProject(_ project: PanelRecentProject, isUnityWanted: Bool) {
        let isOpeningUnity = project.isOpeningUnity(whenWanted: isUnityWanted)
        onLeavingForEditor?()
        Task {
            showNotice(await HubClient.openProject(project, isOpeningUnity: isOpeningUnity))
            await refresh()
        }
    }

    // One task opens at once; several are offered in a menu.
    func openTask(_ session: PanelSession) {
        if session.tasks.count == 1, let task = session.tasks.first {
            open(task: task)
        }
        else {
            settingsMenu.showTaskMenu(session.tasks)
        }
    }

    // A code needs the tracker link from the settings; without one yet, asks for it first.
    func open(task: String) {
        let url: URL?
        if task.hasPrefix("http://") || task.hasPrefix("https://") {
            url = URL(string: task)
        }
        else {
            if taskLinkTemplate.isEmpty {
                settingsMenu.askForTaskLinkTemplate()
            }
            let encoded = task.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? task
            url = taskLinkTemplate.isEmpty ? nil : URL(string: taskLinkTemplate.replacingOccurrences(of: "{code}", with: encoded))
        }
        guard let url else { return }
        onLeavingForEditor?()
        NSWorkspace.shared.open(url)
    }

    func openArtifact(_ session: PanelSession) {
        onLeavingForEditor?()
        Task { await HubClient.openArtifact(session) }
    }

    func showUnityEditor(pid: Int32) {
        guard let editor = NSRunningApplication(processIdentifier: pid) else { return }
        onLeavingForEditor?()
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: editor)
            editor.activate()
        }
        else {
            editor.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func moveGroup(_ movedId: String, to index: Int) {
        var order = groups.filter(\.isReorderable).map(\.id)
        guard let from = order.firstIndex(of: movedId) else { return }
        order.remove(at: from)
        order.insert(movedId, at: min(max(index, 0), order.count))
        saveGroupOrder(order)
    }

    func moveGroup(_ movedId: String, by offset: Int) {
        var order = groups.filter(\.isReorderable).map(\.id)
        guard let from = order.firstIndex(of: movedId) else { return }
        let to = min(max(from + offset, 0), order.count - 1)
        order.remove(at: from)
        order.insert(movedId, at: to)
        saveGroupOrder(order)
    }

    func renameTask(_ group: SessionGroup, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != group.title else { return }
        applyTaskName(trimmed, to: group.sessions, replacingGroupId: group.id)
    }

    func renameSession(_ session: PanelSession, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != session.title else { return }
        Task {
            if let reason = await HubClient.rename(session, to: trimmed) {
                showNotice(reason)
            }
            await refresh()
        }
    }

    func mergeTask(_ sourceId: String, into target: SessionGroup) {
        guard let source = groups.first(where: { $0.id == sourceId }), source.id != target.id else { return }
        applyTaskName(target.title, to: source.sessions, replacingGroupId: source.id)
    }

    func resetGroupOrder() {
        groupOrderByMode = [:]
    }

    private func applyTaskName(_ name: String, to sessions: [PanelSession], replacingGroupId: String) {
        replaceSavedGroupId(replacingGroupId, with: name.lowercased())

        Task {
            var failures: [String] = []
            for session in sessions {
                if let reason = await HubClient.rename(session, to: name) {
                    failures.append(reason)
                }
            }
            if failures.isEmpty == false {
                showNotice(failures.joined(separator: "\n"))
            }
            await refresh()
        }
    }

    private func showNotice(_ text: String?) {
        guard let text else { return }
        notice = text
        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if notice == text {
                notice = nil
            }
        }
    }

    private func replaceSavedGroupId(_ oldId: String, with newId: String) {
        var order = readGroupOrder()
        guard let index = order.firstIndex(of: oldId) else { return }
        if order.contains(newId) {
            order.remove(at: index)
        }
        else {
            order[index] = newId
        }
        groupOrderByMode[groupingMode.rawValue] = order
    }

    private func readGroupOrder() -> [String] {
        groupOrderByMode[groupingMode.rawValue] ?? []
    }

    // Groups that are not on screen right now keep their saved place after the visible ones.
    private func saveGroupOrder(_ visibleOrder: [String]) {
        let hidden = readGroupOrder().filter { visibleOrder.contains($0) == false }
        groupOrderByMode[groupingMode.rawValue] = visibleOrder + hidden
    }

    // Apart from the agents' refresh, which slows down while the panel is closed: the menu bar icon flags a frozen Handy.
    private func startHandyCheckLoop() {
        handyCheckLoop = Task { [weak self] in
            while Task.isCancelled == false {
                self?.checkHandy()
                try? await Task.sleep(for: .seconds(Self.handyCheckIntervalSeconds))
            }
        }
    }

    private func checkHandy() {
        let isFrozen = HandyApp.isFrozen()
        if isHandyFrozen != isFrozen {
            isHandyFrozen = isFrozen
        }
    }

    private func startRefreshLoop() {
        refreshLoop?.cancel()
        let interval = isPanelOpen ? Self.openPanelRefreshSeconds : Self.closedPanelRefreshSeconds
        refreshLoop = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }
}
