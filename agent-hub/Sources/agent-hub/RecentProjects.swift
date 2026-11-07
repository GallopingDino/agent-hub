import Foundation

struct UnityProjectState: Codable {
    let version: String
    let isInstalled: Bool
    let isRunning: Bool
}

struct RecentProject: Codable {
    let name: String
    let directory: String
    let ide: String
    let lastOpenedAt: Date?
    let unity: UnityProjectState?
}

// Projects the IDEs remember that are closed now, most recent first.
enum RecentProjectsReader {
    static func read() -> [RecentProject] {
        let unityEditorPids = ProcessTable().unityEditorPidByProject
        let remembered = IdeIntegrations.all.flatMap { ide in ide.readRecentProjects().map { (ide, $0) } }
        let allDirectories = remembered.map(\.1.directory)

        var seenDirectories: Set<String> = []
        return remembered
            .sorted { ($0.1.lastActivatedAt ?? .distantPast) > ($1.1.lastActivatedAt ?? .distantPast) }
            .filter { _, project in
                project.isOpen == false
                    && FileManager.default.fileExists(atPath: project.directory)
                    && isInsideAnother(project.directory, allDirectories) == false
                    && seenDirectories.insert(project.directory).inserted
            }
            .map { ide, project in
                RecentProject(name: project.displayName, directory: project.directory, ide: ide.name, lastOpenedAt: project.lastActivatedAt, unity: readUnityState(project.directory, unityEditorPids))
            }
    }

    // Skips files an IDE once opened from deep inside another project, such as a package cache.
    private static func isInsideAnother(_ directory: String, _ allDirectories: [String]) -> Bool {
        allDirectories.contains { directory.hasPrefix($0 + "/") }
    }

    private static func readUnityState(_ directory: String, _ unityEditorPids: [String: Int32]) -> UnityProjectState? {
        guard let version = UnityEditorLauncher.readEditorVersion(ofProject: directory) else { return nil }
        return UnityProjectState(version: version, isInstalled: UnityEditorLauncher.findEditorApp(version: version) != nil, isRunning: unityEditorPids[directory] != nil)
    }
}

enum ProjectOpener {
    // Returns nil on success, otherwise what went wrong.
    static func open(directory: String, isOpeningUnity: Bool) -> String? {
        let normalized = ProcessTable.normalize(directory)
        let match = IdeIntegrations.all.lazy.compactMap { ide in ide.readRecentProjects().first { $0.directory == normalized }.map { (ide, $0) } }.first
        guard let (ide, project) = match else { return "no IDE remembers '\(directory)'" }
        guard ide.openProject(project) else { return "\(ide.name) could not open '\(project.displayName)'" }
        guard isOpeningUnity, let version = UnityEditorLauncher.readEditorVersion(ofProject: normalized) else { return nil }
        guard ProcessTable().unityEditorPidByProject[normalized] == nil else { return nil }
        guard let editorApp = UnityEditorLauncher.findEditorApp(version: version) else { return "Unity \(version) is not installed" }
        return UnityEditorLauncher.launch(editorApp, project: normalized) ? nil : "Unity \(version) could not open '\(project.displayName)'"
    }
}
