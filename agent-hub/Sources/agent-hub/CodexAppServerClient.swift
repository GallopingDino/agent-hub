import Foundation

struct CodexRateLimits {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    // Available full resets, the one that expires first first.
    let resetCreditIds: [String]
}

struct CodexThread {
    let id: String
    let cwd: String
    let name: String?
    let preview: String?
    let statusType: String
    let activeFlags: [String]
    let updatedAt: Double
    let createdAt: Double
    let rolloutPath: String?
    let isSubagent: Bool
}

// Speaks JSON-RPC to the Codex app-server daemon, which owns every interactive Codex session; the socket expects WebSocket framing.
final class CodexAppServerClient {
    private static let timeoutSeconds = 2

    private let socket: Int32

    private var nextRequestId = 1
    private var buffer = Data()

    private static var socketPath: String {
        let link = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/app-server-control/app-server-control.sock")
        return link.resolvingSymlinksInPath().path
    }

    private init(socket: Int32) {
        self.socket = socket
    }

    deinit {
        close(socket)
    }

    static func connect() -> CodexAppServerClient? {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }

        let client = CodexAppServerClient(socket: descriptor)
        guard client.upgradeToWebSocket(), client.initializeSession() else { return nil }
        return client
    }

    func listLoadedThreads() -> [CodexThread] {
        guard let result = call("thread/loaded/list", [:]), let ids = result["data"] as? [String] else { return [] }
        return ids.compactMap(readThread)
    }

    func setThreadName(_ threadId: String, to name: String) -> Bool {
        call("thread/name/set", ["threadId": threadId, "name": name]) != nil
    }

    func readRateLimits() -> CodexRateLimits? {
        guard let result = call("account/rateLimits/read", [:]), let limits = result["rateLimits"] as? [String: Any] else { return nil }
        return CodexRateLimits(fiveHour: readRateLimitWindow(limits["primary"]), weekly: readRateLimitWindow(limits["secondary"]), resetCreditIds: readAvailableResetCreditIds(result["rateLimitResetCredits"]))
    }

    func consumeResetCredit(_ creditId: String) -> Bool {
        call("account/rateLimitResetCredit/consume", ["creditId": creditId, "idempotencyKey": UUID().uuidString]) != nil
    }

    private func readAvailableResetCreditIds(_ value: Any?) -> [String] {
        let credits = (value as? [String: Any])?["credits"] as? [[String: Any]] ?? []
        return credits
            .filter { $0["status"] as? String == "available" }
            .sorted { (($0["expiresAt"] as? NSNumber)?.doubleValue ?? .infinity) < (($1["expiresAt"] as? NSNumber)?.doubleValue ?? .infinity) }
            .compactMap { $0["id"] as? String }
    }

    private func readRateLimitWindow(_ value: Any?) -> UsageWindow? {
        guard let window = value as? [String: Any],
              let usedPercent = (window["usedPercent"] as? NSNumber)?.intValue,
              let resetsAt = (window["resetsAt"] as? NSNumber)?.doubleValue else { return nil }
        return UsageWindow(usedPercent: usedPercent, resetsAt: Date(timeIntervalSince1970: resetsAt))
    }

    private func readThread(_ threadId: String) -> CodexThread? {
        guard let result = call("thread/read", ["threadId": threadId, "includeTurns": false]),
              let thread = result["thread"] as? [String: Any],
              let cwd = thread["cwd"] as? String else { return nil }

        let status = thread["status"] as? [String: Any]
        return CodexThread(
            id: threadId,
            cwd: cwd,
            name: thread["name"] as? String,
            preview: thread["preview"] as? String,
            statusType: status?["type"] as? String ?? "notLoaded",
            activeFlags: status?["activeFlags"] as? [String] ?? [],
            updatedAt: (thread["updatedAt"] as? NSNumber)?.doubleValue ?? 0,
            createdAt: (thread["createdAt"] as? NSNumber)?.doubleValue ?? 0,
            rolloutPath: thread["path"] as? String,
            isSubagent: thread["parentThreadId"] is String
        )
    }

    private func initializeSession() -> Bool {
        guard call("initialize", ["clientInfo": ["name": "agent-hub", "version": "1"]]) != nil else { return false }
        return sendMessage(["jsonrpc": "2.0", "method": "initialized"])
    }

    private func call(_ method: String, _ params: [String: Any]) -> [String: Any]? {
        let requestId = nextRequestId
        nextRequestId += 1
        guard sendMessage(["jsonrpc": "2.0", "id": requestId, "method": method, "params": params]) else { return nil }

        while let message = receiveMessage() {
            guard message["id"] as? Int == requestId else { continue }
            return message["result"] as? [String: Any]
        }
        return nil
    }

    // MARK: - WebSocket

    private func upgradeToWebSocket() -> Bool {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        guard writeAll(Data(request.utf8)) else { return false }

        let headerEnd = Data("\r\n\r\n".utf8)
        while buffer.range(of: headerEnd) == nil {
            guard readMore() else { return false }
        }
        let range = buffer.range(of: headerEnd)!
        let header = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
        buffer.removeSubrange(..<range.upperBound)
        return header.hasPrefix("HTTP/1.1 101")
    }

    private func sendMessage(_ message: [String: Any]) -> Bool {
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return false }

        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        }
        else if payload.count <= UInt16.max {
            frame.append(0x80 | 126)
            frame.append(contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian, Array.init))
        }
        else {
            frame.append(0x80 | 127)
            frame.append(contentsOf: withUnsafeBytes(of: UInt64(payload.count).bigEndian, Array.init))
        }

        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        return writeAll(frame)
    }

    private func receiveMessage() -> [String: Any]? {
        while true {
            guard let (opcode, payload) = receiveFrame() else { return nil }
            switch opcode {
            case 0x1:
                if let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                    return message
                }
            case 0x8:
                return nil
            default:
                continue
            }
        }
    }

    private func receiveFrame() -> (opcode: UInt8, payload: Data)? {
        guard fillBuffer(to: 2) else { return nil }
        let opcode = buffer[buffer.startIndex] & 0x0f
        var length = Int(buffer[buffer.startIndex + 1] & 0x7f)
        var headerLength = 2

        if length == 126 {
            guard fillBuffer(to: 4) else { return nil }
            length = buffer.subdata(in: buffer.startIndex + 2 ..< buffer.startIndex + 4).reduce(0) { $0 << 8 | Int($1) }
            headerLength = 4
        }
        else if length == 127 {
            guard fillBuffer(to: 10) else { return nil }
            length = buffer.subdata(in: buffer.startIndex + 2 ..< buffer.startIndex + 10).reduce(0) { $0 << 8 | Int($1) }
            headerLength = 10
        }

        guard fillBuffer(to: headerLength + length) else { return nil }
        let payload = buffer.subdata(in: buffer.startIndex + headerLength ..< buffer.startIndex + headerLength + length)
        buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + headerLength + length)
        return (opcode, payload)
    }

    private func fillBuffer(to count: Int) -> Bool {
        while buffer.count < count {
            guard readMore() else { return false }
        }
        return true
    }

    private func readMore() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = read(socket, &chunk, chunk.count)
        guard count > 0 else { return false }
        buffer.append(contentsOf: chunk[..<count])
        return true
    }

    private func writeAll(_ data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { write(socket, $0.baseAddress! + offset, data.count - offset) }
            guard written > 0 else { return false }
            offset += written
        }
        return true
    }
}
