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
}

enum IdeIntegrations {
    static let all: [any IdeIntegration] = [RiderIntegration()]

    static func readOpenProjectDirectories() -> Set<String> {
        Set(all.flatMap { $0.readRecentProjects() }.filter(\.isOpen).map(\.directory))
    }
}
