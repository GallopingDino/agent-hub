import AppKit

// Handy (github.com/cjpais/Handy), a speech-to-text app, sometimes hangs while it starts recording and stays on screen dead.
enum HandyApp {
    private static let bundleIdentifier = "com.pais.handy"
    private static let startCalledMarker = "TranscribeAction::start called"
    private static let startCompletedMarker = "TranscribeAction::start completed"
    // A healthy start takes well under a second.
    private static let hangSeconds: TimeInterval = 5
    private static let logTailBytes = 256 * 1024
    private static let exitWaitSeconds: TimeInterval = 3

    private static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(bundleIdentifier)/handy.log")
    }

    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    // Frozen: the last recording start never finished, and the log has been silent since, in the Handy that runs now.
    static func isFrozen() -> Bool {
        guard let handy = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let modified = (try? FileManager.default.attributesOfItem(atPath: logFile.path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) > hangSeconds,
              let lines = readLogTail()
        else { return false }

        guard let startIndex = lines.lastIndex(where: { $0.contains(startCalledMarker) }) else { return false }
        if lines[startIndex...].contains(where: { $0.contains(startCompletedMarker) }) {
            return false
        }
        guard let launchDate = handy.launchDate, let startDate = readDate(of: lines[startIndex], logModified: modified, lastLine: lines.last) else { return true }
        return startDate >= launchDate
    }

    // Returns nil on success, otherwise the reason.
    static func restart() async -> String? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let appUrl = running.first?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return "Handy is not installed"
        }

        for handy in running {
            kill(handy.processIdentifier, SIGTERM)
        }
        await waitForExit(running)
        for handy in running where handy.isTerminated == false {
            handy.forceTerminate()
        }
        await waitForExit(running)

        do {
            try await NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration())
            return nil
        }
        catch {
            return "could not start Handy: \(error.localizedDescription)"
        }
    }

    private static func waitForExit(_ apps: [NSRunningApplication]) async {
        let deadline = Date().addingTimeInterval(exitWaitSeconds)
        while apps.contains(where: { $0.isTerminated == false }) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func readLogTail() -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: logFile) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(logTailBytes) ? size - UInt64(logTailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
    }

    // Lines start with "[2026-11-07][16:03:31]" in a time zone the log does not name; the file's own modification time
    // next to its last line tells the offset.
    private static func readDate(of line: Substring, logModified: Date, lastLine: Substring?) -> Date? {
        guard let lastLine, let stamp = parseStamp(line), let lastStamp = parseStamp(lastLine) else { return nil }
        let quarterHour: TimeInterval = 15 * 60
        let offset = ((logModified.timeIntervalSince(lastStamp)) / quarterHour).rounded() * quarterHour
        return stamp.addingTimeInterval(offset)
    }

    private static func parseStamp(_ line: Substring) -> Date? {
        guard line.count >= 22 else { return nil }
        let stamp = line.prefix(22).replacingOccurrences(of: "][", with: " ").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: stamp)
    }
}
