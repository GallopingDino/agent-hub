import Foundation

enum RiderRecentProjects {
    private static let openEntryPattern = try! NSRegularExpression(pattern: "<entry key=\"([^\"]+)\">\\s*(?:<value>\\s*)?<RecentProjectMetaInfo [^>]*opened=\"true\"")

    // Rider marks currently open solutions with opened="true" in its recent-solutions list.
    static func readOpenProjectPaths() -> Set<String> {
        guard let file = findRecentSolutionsFile(), let xml = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: Set<String> = []
        for match in openEntryPattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            guard let keyRange = Range(match.range(at: 1), in: xml) else { continue }
            var path = xml[keyRange].replacingOccurrences(of: "$USER_HOME$", with: home)
            if ["sln", "slnx", "csproj"].contains((path as NSString).pathExtension) {
                path = (path as NSString).deletingLastPathComponent
            }
            paths.insert(ProcessTable.normalize(path))
        }
        return paths
    }

    private static func findRecentSolutionsFile() -> URL? {
        let jetBrains = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JetBrains")
        let directories = (try? FileManager.default.contentsOfDirectory(at: jetBrains, includingPropertiesForKeys: nil)) ?? []
        return directories
            .filter { $0.lastPathComponent.hasPrefix("Rider") }
            .map { $0.appendingPathComponent("options/recentSolutions.xml") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private static func modificationDate(_ file: URL) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date) ?? .distantPast
    }
}
