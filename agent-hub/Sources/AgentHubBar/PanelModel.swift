import AppKit
import SwiftUI

@MainActor
final class PanelModel: ObservableObject {
    private static let openPanelRefreshSeconds: UInt64 = 10
    private static let closedPanelRefreshSeconds: UInt64 = 120

    @AppStorage("isOpeningEditedFilesOnFocus") var isOpeningEditedFilesOnFocus = true

    @Published private(set) var status: PanelStatus?
    @Published private(set) var isRefreshing = false

    private var isPanelOpen = false
    private var refreshLoop: Task<Void, Never>?

    var attentionCount: Int {
        status?.sessions.filter(\.isNeedingUser).count ?? 0
    }

    init() {
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
