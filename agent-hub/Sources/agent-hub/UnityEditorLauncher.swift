import ChildProcess
import Foundation

enum UnityEditorLauncher {
    private static let defaultEditorsDirectory = "/Applications/Unity/Hub/Editor"

    static func readEditorVersion(ofProject directory: String) -> String? {
        guard let text = try? String(contentsOfFile: directory + "/ProjectSettings/ProjectVersion.txt", encoding: .utf8) else { return nil }
        let line = text.split(separator: "\n").first { $0.hasPrefix("m_EditorVersion:") }
        return line.map { $0.dropFirst("m_EditorVersion:".count).trimmingCharacters(in: .whitespaces) }
    }

    static func findEditorApp(version: String) -> String? {
        findEditorsDirectories()
            .map { "\($0)/\(version)/Unity.app" }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    static func launch(_ editorApp: String, project directory: String) -> Bool {
        ChildProcess.run("/usr/bin/open", ["-na", editorApp, "--args", "-projectPath", directory])?.isSuccess ?? false
    }

    // Unity Hub keeps a second install location, if the user picked one, as a bare JSON string.
    private static func findEditorsDirectories() -> [String] {
        let setting = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UnityHub/secondaryInstallPath.json")
        guard let data = try? Data(contentsOf: setting),
              let path = try? JSONDecoder().decode(String.self, from: data),
              path.isEmpty == false else { return [defaultEditorsDirectory] }
        return [defaultEditorsDirectory, path]
    }
}
