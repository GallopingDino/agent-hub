import Foundation

struct HubConfig: Decodable {
    let cloneRoots: [String]
    let staleAfterHours: Double
    let openableExtensions: [String]

    static let fallback = HubConfig(
        cloneRoots: [],
        staleAfterHours: 24,
        openableExtensions: ["cs", "md", "json", "yaml", "yml", "asmdef", "asmref", "shader", "hlsl", "cginc", "uxml", "uss", "txt", "xml", "sh", "py"]
    )

    static var configFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/agent-hub/config.json")
    }

    static func load() -> HubConfig {
        guard let data = try? Data(contentsOf: configFile) else { return fallback }
        return (try? JSONDecoder().decode(HubConfig.self, from: data)) ?? fallback
    }

    func findClonePaths() -> [String] {
        var clones: [String] = []
        for root in cloneRoots {
            let rootPath = (root as NSString).expandingTildeInPath
            let children = (try? FileManager.default.contentsOfDirectory(atPath: rootPath)) ?? []
            for child in children.sorted() {
                let path = rootPath + "/" + child
                if GitInspector.isRepository(path) {
                    clones.append(path)
                }
            }
        }
        return clones
    }

    func isOpenable(_ path: String) -> Bool {
        openableExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}
