import Foundation

struct WorktreeChangesCache {
    private struct CachedCount: Codable {
        let checkedAt: Date
        let changedCount: Int
    }

    private static let maxAgeSeconds: TimeInterval = 300

    private static var cacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/agent-hub/worktree-changes.json")
    }

    private var counts: [String: CachedCount]

    init() {
        let data = try? Data(contentsOf: Self.cacheFile)
        counts = data.flatMap { try? JSONDecoder().decode([String: CachedCount].self, from: $0) } ?? [:]
    }

    mutating func countChangedFiles(in clonePath: String) -> Int? {
        if let cached = counts[clonePath], Date().timeIntervalSince(cached.checkedAt) < Self.maxAgeSeconds {
            return cached.changedCount
        }
        guard let changedCount = GitInspector.countChangedTrackedFiles(in: clonePath) else { return nil }
        counts[clonePath] = CachedCount(checkedAt: Date(), changedCount: changedCount)
        return changedCount
    }

    func save() {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.cacheFile, options: .atomic)
    }
}
