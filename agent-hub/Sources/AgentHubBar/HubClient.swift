import ChildProcess
import Foundation

enum HubClient {
    private static var executable: URL {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/agent-hub")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("agent-hub")
    }

    static func fetchStatus() async -> PanelStatus? {
        guard let output = await run(["status", "--json"]).output else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PanelStatus.self, from: output)
        }
        catch {
            HubLog.write("agent-hub status could not be decoded: \(error)")
            return nil
        }
    }

    static func fetchUsage(isBypassingCache: Bool) async -> [PanelAgentUsage]? {
        guard let output = await run(["usage", "--json"] + (isBypassingCache ? ["--fresh"] : [])).output else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([PanelAgentUsage].self, from: output)
    }

    static func fetchRecentProjects() async -> [PanelRecentProject]? {
        guard let output = await run(["projects", "--json"]).output else { return nil }
        return try? JSONDecoder().decode([PanelRecentProject].self, from: output)
    }

    // Returns nil on success, otherwise the reason agent-hub gave.
    static func openProject(_ project: PanelRecentProject, isOpeningUnity: Bool) async -> String? {
        let result = await run(["open-project", project.directory] + (isOpeningUnity ? ["--with-unity"] : []))
        guard result.output == nil else { return nil }
        let reason = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "could not open '\(project.name)'" : reason
    }

    // Returns nil on success, otherwise one line per agent that stayed asleep.
    static func wakeUpAgents() async -> String? {
        let result = await run(["wake-up"])
        guard result.output == nil else { return nil }
        let reason = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "could not wake up the agents" : reason
    }

    // Returns nil on success, otherwise one line per clone that stayed open.
    static func closeClones(_ clones: [PanelClone]) async -> String? {
        let result = await run(["close-clone"] + clones.map(\.name))
        guard result.output == nil else { return nil }
        let reason = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "could not close the unused clones" : reason
    }

    static func showAgent(_ session: PanelSession, isOpeningEditedFiles: Bool) async {
        _ = await run([isOpeningEditedFiles ? "review" : "focus", String(session.pid)]).output
    }

    // Returns nil on success, otherwise the reason agent-hub gave.
    static func rename(_ session: PanelSession, to newName: String) async -> String? {
        let result = await run(["rename", String(session.pid), newName])
        guard result.output == nil else { return nil }
        let reason = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "cannot rename '\(session.title)': agent-hub failed" : reason
    }

    // Returns nil on success, otherwise the reason agent-hub gave.
    static func close(_ session: PanelSession, isClosingProject: Bool) async -> String? {
        let result = await run(["close", String(session.pid)] + (isClosingProject ? ["--with-project"] : []))
        guard result.output == nil else { return nil }
        let reason = result.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "could not close '\(session.title)'" : reason
    }

    static func openArtifact(_ session: PanelSession) async {
        _ = await run(["open-artifact", String(session.pid)]).output
    }

    private static func run(_ arguments: [String]) async -> (output: Data?, errorText: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let result = ChildProcess.run(executable.path, arguments) else {
                    HubLog.write("cannot start \(executable.path)")
                    continuation.resume(returning: (nil, "cannot start agent-hub"))
                    return
                }

                let errorText = String(decoding: result.errorOutput, as: UTF8.self)
                if result.isSuccess == false || errorText.isEmpty == false {
                    HubLog.write("agent-hub \(arguments.joined(separator: " ")) exited with \(result.exitStatus): \(errorText)")
                }
                continuation.resume(returning: (result.isSuccess ? result.output : nil, errorText))
            }
        }
    }
}
