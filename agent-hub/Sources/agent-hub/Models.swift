import Foundation

enum AgentState: String, Codable {
    case waiting
    case review
    case working
    case idle
    case stale

    var sortOrder: Int {
        switch self {
        case .waiting: return 0
        case .review: return 1
        case .working: return 2
        case .idle: return 3
        case .stale: return 4
        }
    }
}

enum AgentKind: String, Codable {
    case claude
    case codex
}

struct AgentSession: Codable {
    let sessionId: String
    let pid: Int32
    let agent: AgentKind
    let name: String?
    let workingDirectory: String
    let clonePath: String?
    let cloneName: String?
    let state: AgentState
    let waitingFor: String?
    let idleSeconds: Int
    let lastMessagePreview: String?
    let lastMessageExcerpt: String?
    let reviewFiles: [String]
    let artifactUrl: String?
    let riderProject: String?
    let hasTerminalTab: Bool
    let unityPid: Int32?
}

struct CloneState: Codable {
    let name: String
    let path: String
    let branch: String?
    let stagedCount: Int
    let changedCount: Int?
    let unityPid: Int32?
    let isOpenInRider: Bool
    let sessionCount: Int
    let isFree: Bool
}

struct HubStatus: Codable {
    let generatedAt: Date
    let isAgentTabsAvailable: Bool
    let sessions: [AgentSession]
    let clones: [CloneState]
}
