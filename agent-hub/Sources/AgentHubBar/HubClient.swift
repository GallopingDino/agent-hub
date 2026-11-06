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

    static func openArtifact(_ session: PanelSession) async {
        _ = await run(["open-artifact", String(session.pid)]).output
    }

    private static func run(_ arguments: [String]) async -> (output: Data?, errorText: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments

                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors

                do {
                    try process.run()
                }
                catch {
                    HubLog.write("cannot start \(executable.path): \(error)")
                    continuation.resume(returning: (nil, "cannot start agent-hub: \(error.localizedDescription)"))
                    return
                }

                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus != 0 || errorText.isEmpty == false {
                    HubLog.write("agent-hub \(arguments.joined(separator: " ")) exited with \(process.terminationStatus): \(errorText)")
                }
                continuation.resume(returning: (process.terminationStatus == 0 ? data : nil, errorText))
            }
        }
    }
}
