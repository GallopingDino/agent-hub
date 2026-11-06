import Foundation

enum StatusTableRenderer {
    static func render(_ status: HubStatus) -> String {
        var lines: [String] = []

        for session in status.sessions {
            let state = session.state.rawValue.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
            let clone = (session.cloneName ?? (session.workingDirectory as NSString).lastPathComponent).padding(toLength: 19, withPad: " ", startingAt: 0)
            let name = (session.name ?? String(session.sessionId.prefix(8))).padding(toLength: 30, withPad: " ", startingAt: 0)
            let idle = formatDuration(session.idleSeconds).padding(toLength: 6, withPad: " ", startingAt: 0)
            let files = session.reviewFiles.isEmpty ? "" : "\(session.reviewFiles.count) files"
            let tab = session.hasTerminalTab ? "" : "  (no Rider tab)"
            lines.append("\(state) \(clone) \(name) \(idle) \(files)\(tab)")
        }

        let unity = status.clones.filter(\.isUnityOpen).map(\.name)
        let free = status.clones.filter(\.isFree).map(\.name)
        lines.append("")
        lines.append("UNITY    " + unity.joined(separator: "  "))
        lines.append("FREE     " + free.joined(separator: "  "))
        if status.isAgentTabsAvailable == false {
            lines.append("Agent Tabs plugin is not reachable: focus and open-files will not work")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatDuration(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
