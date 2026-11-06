import Foundation

// Transcripts grow to hundreds of megabytes, so each one is scanned once and then only from where the last scan stopped.
struct ArtifactLinkCache {
    private struct ScanProgress: Codable {
        let scannedBytes: UInt64
        let artifactUrl: String?
    }

    private static let chunkSize = 8 * 1024 * 1024
    private static let chunkOverlap = 256
    private static let linkMarker = Data("claude.ai/artifact/".utf8)
    private static let publishResultPrefixes = [Data("url\\\":\\\"https://".utf8), Data("url\":\"https://".utf8)]

    private static var cacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/agent-hub/artifact-links.json")
    }

    private var progressBySession: [String: ScanProgress]

    init() {
        let data = try? Data(contentsOf: Self.cacheFile)
        progressBySession = data.flatMap { try? JSONDecoder().decode([String: ScanProgress].self, from: $0) } ?? [:]
    }

    mutating func findLatestArtifactUrl(of session: ClaudeSessionRecord) -> String? {
        let transcript = ClaudeSessionReader.findTranscript(of: session)
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        var progress = progressBySession[session.sessionId] ?? ScanProgress(scannedBytes: 0, artifactUrl: nil)
        if size < progress.scannedBytes {
            progress = ScanProgress(scannedBytes: 0, artifactUrl: nil)
        }

        var offset = progress.scannedBytes > UInt64(Self.chunkOverlap) ? progress.scannedBytes - UInt64(Self.chunkOverlap) : 0
        var artifactUrl = progress.artifactUrl
        while offset < size {
            try? handle.seek(toOffset: offset)
            guard let chunk = try? handle.read(upToCount: Self.chunkSize), chunk.isEmpty == false else { break }
            if let found = Self.findLastPublishedUrl(in: chunk) {
                artifactUrl = found
            }
            let advanced = offset + UInt64(chunk.count)
            offset = advanced >= size ? size : advanced - UInt64(Self.chunkOverlap)
        }

        progressBySession[session.sessionId] = ScanProgress(scannedBytes: size, artifactUrl: artifactUrl)
        return artifactUrl
    }

    func save() {
        guard let data = try? JSONEncoder().encode(progressBySession) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.cacheFile, options: .atomic)
    }

    private static func findLastPublishedUrl(in chunk: Data) -> String? {
        var lastUrl: String?
        var searchStart = chunk.startIndex
        while let range = chunk.range(of: linkMarker, in: searchStart..<chunk.endIndex) {
            searchStart = range.upperBound
            guard isPublishResult(chunk, linkStart: range.lowerBound) else { continue }

            var idEnd = range.upperBound
            while idEnd < chunk.endIndex, isArtifactIdByte(chunk[idEnd]) {
                idEnd += 1
            }
            if idEnd > range.upperBound {
                lastUrl = "https://claude.ai/artifact/" + String(decoding: chunk[range.upperBound..<idEnd], as: UTF8.self)
            }
        }
        return lastUrl
    }

    private static func isPublishResult(_ chunk: Data, linkStart: Data.Index) -> Bool {
        publishResultPrefixes.contains { prefix in
            guard linkStart - chunk.startIndex >= prefix.count else { return false }
            return chunk[(linkStart - prefix.count)..<linkStart] == prefix
        }
    }

    private static func isArtifactIdByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D || byte == 0x5F
    }
}
