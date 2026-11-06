import Foundation

let usage = """
agent-hub — status of Claude agents across local clones

usage:
  agent-hub status [--json]       sessions, review queue, clones, open Unity editors
  agent-hub focus <session>       show the agent's terminal tab in Rider
  agent-hub open-files <session>  open the agent's still-changed code files in Rider (no prefabs/scenes/assets)
  agent-hub review <session>      open-files, then focus
  agent-hub open-artifact <session>  open the last artifact the agent published

<session> is a session name, a session id prefix or a pid.
"""

func findSession(_ query: String, in status: HubStatus) -> AgentSession? {
    if let pid = Int32(query), let session = status.sessions.first(where: { $0.pid == pid }) {
        return session
    }
    if let session = status.sessions.first(where: { $0.name?.caseInsensitiveCompare(query) == .orderedSame }) {
        return session
    }
    let byId = status.sessions.filter { $0.sessionId.hasPrefix(query) }
    if byId.count == 1 {
        return byId[0]
    }
    let byName = status.sessions.filter { $0.name?.localizedCaseInsensitiveContains(query) ?? false }
    return byName.count == 1 ? byName[0] : nil
}

func exitWithError(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func report(_ reply: AgentTabsReply) {
    guard reply.ok else { exitWithError(reply.error ?? "Agent Tabs request failed") }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let config = HubConfig.load()

switch arguments.first {
case "status":
    let status = StatusBuilder.build(config: config)
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(status), as: UTF8.self))
    }
    else {
        print(StatusTableRenderer.render(status))
    }

case "focus", "open-files", "review", "open-artifact":
    guard arguments.count >= 2 else { exitWithError(usage) }
    let query = arguments.dropFirst().joined(separator: " ")
    let status = StatusBuilder.build(config: config)
    guard let session = findSession(query, in: status) else { exitWithError("no single session matches '\(query)'") }

    let openableFiles = session.reviewFiles.filter(config.isOpenable)
    let riderProject = session.riderProject ?? session.clonePath ?? session.workingDirectory

    switch arguments[0] {
    case "focus":
        report(AgentTabsClient.focusTab(ofProcess: session.pid))
    case "open-files":
        guard openableFiles.isEmpty == false else { exitWithError("session '\(session.name ?? session.sessionId)' has no still-changed code files") }
        report(AgentTabsClient.openFiles(openableFiles, inProject: riderProject))
    case "review":
        if openableFiles.isEmpty == false {
            report(AgentTabsClient.openFiles(openableFiles, inProject: riderProject))
        }
        report(AgentTabsClient.focusTab(ofProcess: session.pid))
    default:
        guard let artifactUrl = session.artifactUrl else { exitWithError("session '\(session.name ?? session.sessionId)' has not published an artifact") }
        _ = ShellCommand.run("/usr/bin/open", [artifactUrl])
    }

default:
    print(usage)
}
