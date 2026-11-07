import Foundation

struct UsageWindow: Codable {
    let usedPercent: Int
    let resetsAt: Date
}

struct AgentUsage: Codable {
    let agent: AgentKind
    // Nil when no 5-hour window is running: the agent is asleep until its next request.
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    // Free resets of both windows the account may spend; nil for an agent that has none.
    let resetCount: Int?
    let error: String?
}

enum AgentUsageReader {
    private struct CachedUsage: Codable {
        let checkedAt: Date
        let usage: [AgentUsage]
    }

    private static let maxCacheAgeSeconds: TimeInterval = 60
    private static let requestTimeoutSeconds: TimeInterval = 5
    private static let codexIdleCheckDelaySeconds: TimeInterval = 1.2
    private static let claudeUsageUrl = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static var cacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/agent-hub/usage.json")
    }

    static func read(isBypassingCache: Bool) -> [AgentUsage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if isBypassingCache == false,
           let data = try? Data(contentsOf: cacheFile),
           let cached = try? decoder.decode(CachedUsage.self, from: data),
           Date().timeIntervalSince(cached.checkedAt) < maxCacheAgeSeconds {
            return cached.usage
        }

        var claude: AgentUsage?
        var codex: AgentUsage?
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) { claude = readClaudeUsage() }
        DispatchQueue.global().async(group: group) { codex = readCodexUsage() }
        group.wait()

        let usage = [claude, codex].compactMap { $0 }
        saveCache(CachedUsage(checkedAt: Date(), usage: usage))
        return usage
    }

    static func forgetCache() {
        try? FileManager.default.removeItem(at: cacheFile)
    }

    private static func readClaudeUsage() -> AgentUsage {
        guard let token = readClaudeAccessToken() else { return AgentUsage(agent: .claude, fiveHour: nil, weekly: nil, resetCount: nil, error: "not signed in") }

        var request = URLRequest(url: claudeUsageUrl, timeoutInterval: requestTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The API never answers CFNetwork's default user agent.
        request.setValue("agent-hub", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: Data?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                body = data
            }
            done.signal()
        }.resume()
        done.wait()

        guard let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return AgentUsage(agent: .claude, fiveHour: nil, weekly: nil, resetCount: nil, error: "usage unavailable")
        }
        return AgentUsage(agent: .claude, fiveHour: activeWindow(readClaudeWindow(json["five_hour"])), weekly: readClaudeWindow(json["seven_day"]), resetCount: nil, error: nil)
    }

    private static func readClaudeAccessToken() -> String? {
        guard let credentials = ShellCommand.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let json = try? JSONSerialization.jsonObject(with: Data(credentials.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }

    private static func readClaudeWindow(_ value: Any?) -> UsageWindow? {
        guard let window = value as? [String: Any],
              let utilization = (window["utilization"] as? NSNumber)?.doubleValue,
              let resetsAtText = window["resets_at"] as? String,
              let resetsAt = parseIsoDate(resetsAtText) else { return nil }
        return UsageWindow(usedPercent: Int(utilization.rounded()), resetsAt: resetsAt)
    }

    private static func readCodexUsage() -> AgentUsage {
        guard let client = CodexAppServerClient.connect(), let limits = client.readRateLimits() else {
            return AgentUsage(agent: .codex, fiveHour: nil, weekly: nil, resetCount: nil, error: "usage unavailable")
        }
        let fiveHour = isCodexWindowIdle(limits.fiveHour, client) ? nil : activeWindow(limits.fiveHour)
        return AgentUsage(agent: .codex, fiveHour: fiveHour, weekly: limits.weekly, resetCount: limits.resetCreditIds.count, error: nil)
    }

    // With no window running, Codex reports an unused window that resets 5 hours from the moment of asking, so its reset time moves.
    private static func isCodexWindowIdle(_ window: UsageWindow?, _ client: CodexAppServerClient) -> Bool {
        guard let window, window.usedPercent == 0 else { return false }
        Thread.sleep(forTimeInterval: codexIdleCheckDelaySeconds)
        guard let again = client.readRateLimits()?.fiveHour else { return false }
        return again.resetsAt != window.resetsAt
    }

    // A window whose reset time has passed still reports its old numbers until the next request opens a new one.
    private static func activeWindow(_ window: UsageWindow?) -> UsageWindow? {
        guard let window, window.resetsAt > Date() else { return nil }
        return window
    }

    // The API sends microseconds, which ISO8601DateFormatter does not parse.
    private static func parseIsoDate(_ text: String) -> Date? {
        let withoutFraction = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: withoutFraction)
    }

    private static func saveCache(_ cached: CachedUsage) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cached) else { return }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)
    }
}
