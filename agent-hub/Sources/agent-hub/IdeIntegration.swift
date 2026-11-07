import Foundation

struct IdeRecentProject {
    let directory: String
    // What the IDE itself opens: a solution file or the directory.
    let openTarget: String
    let displayName: String
    let lastActivatedAt: Date?
    let isOpen: Bool
}

// Everything the hub needs from an IDE; the rest of the code never names a specific one.
protocol IdeIntegration {
    var name: String { get }

    func readRecentProjects() -> [IdeRecentProject]
    func openProject(_ project: IdeRecentProject) -> Bool
    func closeProject(directory: String) -> Bool
}

enum IdeIntegrations {
    static let all: [any IdeIntegration] = [RiderIntegration()]

    // Returns false when no IDE has the project open or the IDE refused.
    static func closeProject(directory: String) -> Bool {
        let normalized = ProcessTable.normalize(directory)
        let owner = all.first { ide in ide.readRecentProjects().contains { $0.isOpen && $0.directory == normalized } }
        return owner?.closeProject(directory: normalized) ?? false
    }

    static func readOpenProjectDirectories() -> Set<String> {
        Set(all.flatMap { $0.readRecentProjects() }.filter(\.isOpen).map(\.directory))
    }
}
