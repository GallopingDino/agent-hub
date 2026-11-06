import AppKit
import SwiftUI

@MainActor
final class PanelModel: ObservableObject {
    private static let openPanelRefreshSeconds: UInt64 = 10
    private static let closedPanelRefreshSeconds: UInt64 = 120

    private let defaults = UserDefaults.standard

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
    @Published private(set) var isRefreshing = false

    private var isPanelOpen = false
    private var refreshLoop: Task<Void, Never>?

    var attentionCount: Int {
        status?.sessions.filter(\.isNeedingUser).count ?? 0
    }

    var groups: [SessionGroup] {
        SessionGrouping.makeGroups(status?.sessions ?? [], mode: groupingMode, savedOrder: readGroupOrder())
    }

    init() {
        isOpeningEditedFilesOnFocus = defaults.object(forKey: "isOpeningEditedFilesOnFocus") as? Bool ?? true
        groupingMode = GroupingMode(rawValue: defaults.string(forKey: "groupingMode") ?? "") ?? .status
        groupOrderByMode = defaults.dictionary(forKey: "groupOrderByMode") as? [String: [String]] ?? [:]
        startRefreshLoop()
    }

    func panelDidOpen() {
        isPanelOpen = true
        startRefreshLoop()
    }

    func panelDidClose() {
        isPanelOpen = false
        startRefreshLoop()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        if let fresh = await HubClient.fetchStatus() {
            status = fresh
        }
        isRefreshing = false
    }

    func showAgent(_ session: PanelSession) {
        let isOpeningFiles = isOpeningEditedFilesOnFocus
        Task { await HubClient.showAgent(session, isOpeningEditedFiles: isOpeningFiles) }
    }

    func openArtifact(_ session: PanelSession) {
        Task { await HubClient.openArtifact(session) }
    }

    func showUnityEditor(pid: Int32) {
        guard let editor = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: editor)
            editor.activate()
        }
        else {
            editor.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func moveGroup(_ movedId: String, before targetId: String) {
        var order = groups.filter(\.isReorderable).map(\.id)
        guard movedId != targetId, let from = order.firstIndex(of: movedId) else { return }
        order.remove(at: from)
        order.insert(movedId, at: order.firstIndex(of: targetId) ?? order.endIndex)
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

    func resetGroupOrder() {
        groupOrderByMode = [:]
    }

    private func readGroupOrder() -> [String] {
        groupOrderByMode[groupingMode.rawValue] ?? []
    }

    // Groups that are not on screen right now keep their saved place after the visible ones.
    private func saveGroupOrder(_ visibleOrder: [String]) {
        let hidden = readGroupOrder().filter { visibleOrder.contains($0) == false }
        groupOrderByMode[groupingMode.rawValue] = visibleOrder + hidden
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
