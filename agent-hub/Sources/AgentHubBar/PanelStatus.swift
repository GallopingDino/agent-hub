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
    let agent: String?
    let name: String?
    let cloneName: String?
    let workingDirectory: String
    let state: String
    let waitingFor: String?
    let idleSeconds: Int
    let lastMessagePreview: String?
    let lastMessageExcerpt: String?
    let reviewFiles: [String]
    let artifactUrl: String?
    let hasTerminalTab: Bool
    let unityPid: Int32?

    var id: String { sessionId }

    var title: String { name ?? String(sessionId.prefix(8)) }

    var projectName: String { cloneName ?? (workingDirectory as NSString).lastPathComponent }

    var isNeedingUser: Bool { state == "waiting" || state == "review" }

    // Claude Code is renamed by typing /rename into its terminal, which would answer a pending question instead.
    var isRenameable: Bool { agent == "codex" || (hasTerminalTab && state != "waiting") }

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

// Mirrors the `agent-hub usage --json` contract.
struct PanelAgentUsage: Decodable {
    private static let lowFiveHourPercentLeft = 20

    let agent: String
    let fiveHour: PanelUsageWindow?
    let weekly: PanelUsageWindow?
    let error: String?

    // No 5-hour window is running, so the next request starts one.
    var isAsleep: Bool { error == nil && fiveHour == nil }

    var isRunningLow: Bool { (fiveHour?.percentLeft ?? 100) < Self.lowFiveHourPercentLeft }

    var agentName: String { agent == "codex" ? "Codex" : "Claude Code" }

    var summary: String {
        if let error {
            return error.prefix(1).uppercased() + error.dropFirst()
        }
        let fiveHourText = fiveHour.map { "5h \($0.percentLeft)% left until \($0.resetsAt.formatted(date: .omitted, time: .shortened))" } ?? "No session"
        let weeklyText = weekly.map { "week \($0.percentLeft)% left" } ?? "week unknown"
        return "\(fiveHourText) · \(weeklyText)"
    }
}

struct PanelUsageWindow: Decodable {
    let usedPercent: Int
    let resetsAt: Date

    var percentLeft: Int { max(0, 100 - usedPercent) }
}

// Mirrors the `agent-hub projects --json` contract.
struct PanelRecentProject: Decodable, Identifiable {
    let name: String
    let directory: String
    let ide: String
    let unity: PanelUnityProject?

    var id: String { directory }

    // Holding Option adds Unity only where that changes what opens.
    var canChooseUnity: Bool { unity.map { $0.isInstalled && $0.isRunning == false } ?? false }

    var parentFolderName: String { ((directory as NSString).deletingLastPathComponent as NSString).lastPathComponent }

    func isOpeningUnity(whenWanted isUnityWanted: Bool) -> Bool {
        isUnityWanted && canChooseUnity
    }

    func describeLaunch(isUnityWanted: Bool) -> String {
        guard let unity else { return ide }
        if unity.isRunning {
            return "\(ide) · Unity already open"
        }
        guard isUnityWanted else { return "\(ide) only" }
        return unity.isInstalled ? "\(ide) + Unity \(unity.version)" : "\(ide) · Unity \(unity.version) not installed"
    }
}

struct PanelUnityProject: Decodable {
    let version: String
    let isInstalled: Bool
    let isRunning: Bool
}
