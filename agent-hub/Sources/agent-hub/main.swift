import Foundation

let usage = """
agent-hub — status of Claude Code and Codex agents across local clones

usage:
  agent-hub status [--json]       sessions, review queue, clones, open Unity editors
  agent-hub sessions --json       live agent sessions only, without Rider tabs (used by the Rider plugin)
  agent-hub usage [--json] [--fresh]  5-hour and weekly limits of Claude Code and Codex (cached for 5 minutes)
  agent-hub wake-up               start a 5-hour window for each agent with one short request outside any project
  agent-hub task <code=link | code | link>...  set the tasks of the Claude Code or Codex session this runs in; --clear forgets them
  agent-hub reset-usage codex     spend one of Codex's free resets of its 5-hour and weekly limits
  agent-hub focus <session>       show the agent's terminal tab in Rider
  agent-hub open-files <session>  open the agent's still-changed code files in Rider (no prefabs/scenes/assets)
  agent-hub review <session>      open-files, then focus
  agent-hub open-artifact <session>  open the last artifact the agent published
  agent-hub focus-unity <session|clone>  bring the clone's Unity editor to the front
  agent-hub rename <session> <new name>  rename a session (Claude Code: types /rename into its tab)
  agent-hub close <session> [--with-project]  close the agent's terminal tab; with --with-project also its IDE window and Unity editor
  agent-hub close-clone <clone>...  close the IDE window and Unity editor of clones with no agent and no local changes
  agent-hub projects [--json]     projects the IDEs remember that are closed now, most recent first
  agent-hub open-project <directory> [--with-unity]  open a remembered project in its IDE, and its Unity editor

<session> is a session name, a session id prefix or a pid.
"""

func findSession(_ query: String, in sessions: [AgentSession]) -> AgentSession? {
    if let pid = Int32(query), let session = sessions.first(where: { $0.pid == pid }) {
        return session
    }
    if let session = sessions.first(where: { $0.name?.caseInsensitiveCompare(query) == .orderedSame }) {
        return session
    }
    let byId = sessions.filter { $0.sessionId.hasPrefix(query) }
    if byId.count == 1 {
        return byId[0]
    }
    let byName = sessions.filter { $0.name?.localizedCaseInsensitiveContains(query) ?? false }
    return byName.count == 1 ? byName[0] : nil
}

func exitWithError(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func printJson<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self))
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
        printJson(status)
    }
    else {
        print(StatusTableRenderer.render(status))
    }

case "sessions":
    printJson(StatusBuilder.buildSessions(config: config, isLookingUpRiderTabs: false))

case "usage":
    let usage = AgentUsageReader.read(isBypassingCache: arguments.contains("--fresh"))
    if arguments.contains("--json") {
        printJson(usage)
    }
    else {
        print(UsageTextRenderer.render(usage))
    }

case "task":
    guard arguments.count >= 2 else { exitWithError(usage) }
    guard let sessionId = TaskStore.findCallingSessionId() else { exitWithError("run this from inside a Claude Code or Codex session") }
    let tasks = arguments.contains("--clear") ? [] : arguments.dropFirst().map(TaskStore.parse)
    guard TaskStore.save(tasks, forSession: sessionId) else { exitWithError("could not save the tasks") }

case "reset-usage":
    guard arguments.count == 2, arguments[1] == AgentKind.codex.rawValue else { exitWithError("only Codex has usage resets: agent-hub reset-usage codex") }
    guard let client = CodexAppServerClient.connect(), let limits = client.readRateLimits() else { exitWithError("cannot reach the Codex app-server") }
    guard let creditId = limits.resetCreditIds.first else { exitWithError("Codex has no resets left") }
    guard client.consumeResetCredit(creditId) else { exitWithError("Codex refused the reset") }

case "wake-up":
    let failures = AgentWaker.wakeUpAgents()
    if failures.isEmpty == false {
        exitWithError(failures.joined(separator: "\n"))
    }

case "focus", "open-files", "review", "open-artifact":
    guard arguments.count >= 2 else { exitWithError(usage) }
    let query = arguments.dropFirst().joined(separator: " ")
    guard let session = findSession(query, in: StatusBuilder.buildSessions(config: config)) else { exitWithError("no single session matches '\(query)'") }

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

case "rename":
    guard arguments.count >= 3 else { exitWithError(usage) }
    guard let session = findSession(arguments[1], in: StatusBuilder.buildSessions(config: config)) else { exitWithError("no single session matches '\(arguments[1])'") }
    let newName = arguments.dropFirst(2).joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
    if let failure = SessionRenamer.rename(session, to: newName) {
        exitWithError("cannot rename '\(session.name ?? session.sessionId)' (\(session.cloneName ?? "no clone")): \(failure)")
    }

case "close":
    guard arguments.count >= 2 else { exitWithError(usage) }
    let query = arguments.dropFirst().filter { $0 != "--with-project" }.joined(separator: " ")
    guard let session = findSession(query, in: StatusBuilder.buildSessions(config: config)) else { exitWithError("no single session matches '\(query)'") }
    if let failure = SessionCloser.close(session, isClosingProject: arguments.contains("--with-project")) {
        exitWithError(failure)
    }

case "close-clone":
    guard arguments.count >= 2 else { exitWithError(usage) }
    let clones = StatusBuilder.build(config: config).clones
    var failures: [String] = []
    for name in arguments.dropFirst() {
        guard let clone = clones.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            failures.append("no clone named '\(name)'")
            continue
        }
        guard clone.isFree else {
            failures.append("\(clone.name) is in use: it has an agent or local changes")
            continue
        }
        if let failure = CloneCloser.close(clone) {
            failures.append(failure)
        }
    }
    if failures.isEmpty == false {
        exitWithError(failures.joined(separator: "\n"))
    }

case "focus-unity":
    guard arguments.count >= 2 else { exitWithError(usage) }
    let query = arguments.dropFirst().joined(separator: " ")
    let status = StatusBuilder.build(config: config)
    let clone = status.clones.first { $0.name.caseInsensitiveCompare(query) == .orderedSame }
    guard let unityPid = clone?.unityPid ?? findSession(query, in: status.sessions)?.unityPid else { exitWithError("no open Unity editor for '\(query)'") }
    guard UnityEditorActivator.activate(pid: unityPid) else { exitWithError("could not activate Unity editor pid \(unityPid)") }

case "projects":
    let projects = RecentProjectsReader.read()
    if arguments.contains("--json") {
        printJson(projects)
    }
    else {
        for project in projects {
            print([project.name, project.ide, project.unity.map { "Unity \($0.version)" }, project.directory].compactMap { $0 }.joined(separator: "  "))
        }
    }

case "open-project":
    guard arguments.count >= 2 else { exitWithError(usage) }
    if let failure = ProjectOpener.open(directory: arguments[1], isOpeningUnity: arguments.contains("--with-unity")) {
        exitWithError(failure)
    }

default:
    print(usage)
}
