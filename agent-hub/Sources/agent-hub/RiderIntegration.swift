import ChildProcess
import Foundation

struct RiderIntegration: IdeIntegration {
    private static let bundleId = "com.jetbrains.rider"
    private static let solutionExtensions: Set<String> = ["sln", "slnx", "csproj"]
    private static let entriesXPath = "//component[@name='RiderRecentProjectsManager']/option[@name='additionalInfo']/map/entry"

    let name = "Rider"

    func readRecentProjects() -> [IdeRecentProject] {
        guard let file = Self.findRecentSolutionsFile(), let document = try? XMLDocument(contentsOf: file) else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let entries = (try? document.nodes(forXPath: Self.entriesXPath)) ?? []
        return entries.compactMap { node in
            guard let entry = node as? XMLElement, let key = entry.attribute(forName: "key")?.stringValue else { return nil }
            let openTarget = key.replacingOccurrences(of: "$USER_HOME$", with: home)
            let info = (try? entry.nodes(forXPath: ".//RecentProjectMetaInfo"))?.first as? XMLElement
            let directory = ProcessTable.normalize(Self.findDirectory(of: openTarget))
            return IdeRecentProject(
                directory: directory,
                openTarget: openTarget,
                displayName: info?.attribute(forName: "displayName")?.stringValue ?? (directory as NSString).lastPathComponent,
                lastActivatedAt: Self.readActivationDate(info),
                isOpen: info?.attribute(forName: "opened")?.stringValue == "true"
            )
        }
    }

    func openProject(_ project: IdeRecentProject) -> Bool {
        ChildProcess.run("/usr/bin/open", ["-b", Self.bundleId, project.openTarget])?.isSuccess ?? false
    }

    // Rider also lists single files it once opened, such as a CMakeLists.txt; their project is the containing directory.
    private static func findDirectory(of openTarget: String) -> String {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: openTarget, isDirectory: &isDirectory)
        let isFile = solutionExtensions.contains((openTarget as NSString).pathExtension) || (exists && isDirectory.boolValue == false)
        return isFile ? (openTarget as NSString).deletingLastPathComponent : openTarget
    }

    private static func readActivationDate(_ info: XMLElement?) -> Date? {
        guard let value = (try? info?.nodes(forXPath: "option[@name='activationTimestamp']/@value"))?.first?.stringValue,
              let milliseconds = Double(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
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
