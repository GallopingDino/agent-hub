import Foundation

enum SessionRenamer {
    private static let stashKey = "\u{13}"
    private static let confirmationTimeoutSeconds = 5.0

    // Ctrl+S stashes any half-typed draft; Claude Code restores it by itself after /rename is submitted.
    static func rename(_ session: AgentSession, to newName: String) -> String? {
        switch session.state {
        case .waiting: return "the agent is waiting for an answer (\(session.waitingFor ?? "input")); typed text would answer it"
        default: break
        }
        guard session.hasTerminalTab else { return "no Rider terminal tab found for this session" }

        let stash = AgentTabsClient.sendText(stashKey, toProcess: session.pid, isPressingEnter: false)
        guard stash.ok else { return stash.error ?? "could not reach the agent's tab" }
        Thread.sleep(forTimeInterval: 0.2)

        let command = AgentTabsClient.sendText("/rename " + newName, toProcess: session.pid, isPressingEnter: true)
        guard command.ok else { return command.error ?? "could not type /rename into the agent's tab" }

        let deadline = Date().addingTimeInterval(confirmationTimeoutSeconds)
        while Date() < deadline {
            if ClaudeSessionReader.readName(ofProcess: session.pid) == newName {
                return nil
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let currentName = ClaudeSessionReader.readName(ofProcess: session.pid) ?? "unknown"
        return "/rename was typed, but the session is still called '\(currentName)' after \(Int(confirmationTimeoutSeconds)) s; check the agent's tab"
    }
}
