import Foundation

enum UsageTextRenderer {
    static func render(_ usage: [AgentUsage]) -> String {
        usage.map { "\(name(of: $0.agent).padding(toLength: 12, withPad: " ", startingAt: 0)) \(describe($0))" }.joined(separator: "\n")
    }

    static func describe(_ usage: AgentUsage) -> String {
        if let error = usage.error {
            return error
        }
        let fiveHour = usage.fiveHour.map { "5h \(100 - $0.usedPercent)% left" } ?? "no session"
        let weekly = usage.weekly.map { "week \(100 - $0.usedPercent)% left" } ?? "week unknown"
        return "\(fiveHour) · \(weekly)"
    }

    private static func name(of agent: AgentKind) -> String {
        switch agent {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
