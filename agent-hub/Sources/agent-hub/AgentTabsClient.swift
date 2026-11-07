import Foundation

struct RiderTerminalTab: Decodable {
    let project: String
    let tab: String?
    let shellPid: Int32?
}

struct AgentTabsReply: Decodable {
    let ok: Bool
    let error: String?
}

enum AgentTabsClient {
    private static let baseUrl = "http://127.0.0.1:63342/api/agent-tabs/"
    private static let timeoutSeconds: TimeInterval = 3
    private static let session = URLSession(configuration: .ephemeral)

    static func listTabs() -> [RiderTerminalTab]? {
        guard let data = request("list", []) else { return nil }
        return try? JSONDecoder().decode([RiderTerminalTab].self, from: data)
    }

    static func focusTab(ofProcess pid: Int32) -> AgentTabsReply {
        send("focus", [URLQueryItem(name: "pid", value: String(pid))])
    }

    static func openFiles(_ paths: [String], inProject project: String) -> AgentTabsReply {
        send("open-files", [URLQueryItem(name: "project", value: project)] + paths.map { URLQueryItem(name: "path", value: $0) })
    }

    static func sendText(_ text: String, toProcess pid: Int32, isPressingEnter: Bool) -> AgentTabsReply {
        send("send-text", [URLQueryItem(name: "pid", value: String(pid)), URLQueryItem(name: "text", value: text), URLQueryItem(name: "execute", value: isPressingEnter ? "true" : "false")])
    }

    static func closeTab(ofProcess pid: Int32) -> AgentTabsReply {
        send("close", [URLQueryItem(name: "pid", value: String(pid))])
    }

    static func closeProject(_ project: String) -> AgentTabsReply {
        send("close-project", [URLQueryItem(name: "project", value: project)])
    }

    private static func send(_ action: String, _ query: [URLQueryItem]) -> AgentTabsReply {
        guard let data = request(action, query) else {
            return AgentTabsReply(ok: false, error: "Agent Tabs plugin is not reachable; is Rider running with the plugin installed?")
        }
        guard let reply = try? JSONDecoder().decode(AgentTabsReply.self, from: data) else {
            return AgentTabsReply(ok: false, error: "unexpected reply from Agent Tabs")
        }
        if reply.error?.hasPrefix("unknown action") == true {
            return AgentTabsReply(ok: false, error: "the Agent Tabs plugin in Rider is outdated and has no '\(action)'; install rider-plugin/out/agent-tabs.jar from disk")
        }
        return reply
    }

    private static func request(_ action: String, _ query: [URLQueryItem]) -> Data? {
        var components = URLComponents(string: baseUrl + action)!
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = timeoutSeconds

        var result: Data?
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: urlRequest) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                result = data
            }
            done.signal()
        }.resume()
        done.wait()
        return result
    }
}
