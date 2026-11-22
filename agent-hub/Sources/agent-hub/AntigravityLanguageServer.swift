import Foundation

// Every agy runs a local language server that answers JSON requests, but only with a token its own child processes
// see. agy takes the token from ANTIGRAVITY_SERVER_CSRF_TOKEN, so the hub starts a short-lived agy of its own with a
// token it knows. agy wants a terminal even while it sits at its first prompt, hence script(1).
enum AntigravityLanguageServer {
    private static let servicePath = "exa.language_server_pb.LanguageServerService/"
    private static let startTimeoutSeconds: TimeInterval = 15
    private static let pollIntervalSeconds: TimeInterval = 0.25
    private static let requestTimeoutSeconds: TimeInterval = 10

    struct Connection {
        let port: Int
        let token: String

        func call(_ method: String, _ body: [String: Any]) -> [String: Any]? {
            AntigravityLanguageServer.post(method, body, port: port, token: token)
        }
    }

    // The helper agy runs here, which tells it apart from the user's sessions.
    static var helperDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/agent-hub/agy-helper").standardizedFileURL
    }

    static func withServer<T>(_ work: (Connection) -> T?) -> T? {
        guard let executable = AgentWaker.findExecutable("agy") else { return nil }
        try? FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)

        let token = UUID().uuidString
        let terminal = Process()
        terminal.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        terminal.arguments = ["-q", "/dev/null", executable]
        terminal.currentDirectoryURL = helperDirectory
        terminal.environment = ProcessInfo.processInfo.environment.merging(["ANTIGRAVITY_SERVER_CSRF_TOKEN": token]) { _, new in new }
        // An open input keeps script from ending at end of file.
        let input = Pipe()
        terminal.standardInput = input
        terminal.standardOutput = FileHandle.nullDevice
        terminal.standardError = FileHandle.nullDevice
        guard (try? terminal.run()) != nil else { return nil }

        var agyPid: Int32?
        defer {
            if let agyPid { kill(agyPid, SIGTERM) }
            terminal.terminate()
            try? input.fileHandleForWriting.close()
        }

        let deadline = Date().addingTimeInterval(startTimeoutSeconds)
        while Date() < deadline {
            agyPid = agyPid ?? findChild(of: terminal.processIdentifier)
            if let agyPid, let port = findHttpPort(of: agyPid, token: token) {
                return work(Connection(port: port, token: token))
            }
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
        return nil
    }

    private static func findChild(of pid: Int32) -> Int32? {
        ShellCommand.run("/usr/bin/pgrep", ["-P", String(pid)])?.split(separator: "\n").first.flatMap { Int32($0) }
    }

    // The server listens on an HTTPS port and an HTTP port; only the HTTP one answers plain JSON.
    private static func findHttpPort(of pid: Int32, token: String) -> Int? {
        let output = ShellCommand.run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-nP", "-Fn"]) ?? ""
        let ports = output.split(separator: "\n").filter { $0.hasPrefix("n") }.compactMap { $0.split(separator: ":").last.flatMap { Int($0) } }
        return ports.first { post("GetStatus", [:], port: $0, token: token) != nil }
    }

    private static func post(_ method: String, _ body: [String: Any], port: Int, token: String) -> [String: Any]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(servicePath)\(method)"), let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: requestTimeoutSeconds)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")

        var answer: [String: Any]?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data {
                answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            done.signal()
        }.resume()
        done.wait()
        return answer
    }
}
