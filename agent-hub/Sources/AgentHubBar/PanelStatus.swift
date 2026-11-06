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
    let unityPid: Int32?

    var id: String { sessionId }

    var title: String { name ?? String(sessionId.prefix(8)) }

    var projectName: String { cloneName ?? (workingDirectory as NSString).lastPathComponent }

    var isNeedingUser: Bool { state == "waiting" || state == "review" }

    // Renaming types /rename into the agent's terminal, which is only safe when it is not busy or asking something.
    var isRenameable: Bool { hasTerminalTab && state != "working" && state != "waiting" }

    var stateOrder: Int {
        switch state {
        case "waiting": return 0
        case "review": return 1
        case "working": return 2
        case "idle": return 3
        default: return 4
        }
    }
}

struct PanelClone: Decodable, Identifiable {
    let name: String
    let unityPid: Int32?
    let isOpenInRider: Bool
    let isFree: Bool

    var id: String { name }

    var isRunning: Bool { unityPid != nil || isOpenInRider }
}
