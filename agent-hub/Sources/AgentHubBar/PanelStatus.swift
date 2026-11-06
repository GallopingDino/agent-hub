import Foundation

// Mirrors the `agent-hub status --json` contract; only the fields the panel shows.
struct PanelStatus: Decodable {
    let generatedAt: Date
    let isAgentTabsAvailable: Bool
    let sessions: [PanelSession]
    let clones: [PanelClone]
}

struct PanelSession: Decodable, Identifiable {
    let sessionId: String
    let pid: Int32
    let name: String?
    let cloneName: String?
    let workingDirectory: String
    let state: String
    let waitingFor: String?
    let idleSeconds: Int
    let lastMessagePreview: String?
    let reviewFiles: [String]
    let artifactUrl: String?
    let hasTerminalTab: Bool

    var id: String { sessionId }

    var title: String { name ?? String(sessionId.prefix(8)) }

    var projectName: String { cloneName ?? (workingDirectory as NSString).lastPathComponent }
}

struct PanelClone: Decodable {
    let name: String
    let isUnityOpen: Bool
    let isFree: Bool
}
