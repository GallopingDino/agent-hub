import Foundation

enum GitInspector {
    private static let gitExecutable = "/usr/bin/git"
    private static let branchRefPrefix = "ref: refs/heads/"

    static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    static func readBranch(of clonePath: String) -> String? {
        guard let head = try? String(contentsOfFile: clonePath + "/.git/HEAD", encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(branchRefPrefix) ? String(trimmed.dropFirst(branchRefPrefix.count)) : String(trimmed.prefix(9))
    }

    static func countStagedFiles(in clonePath: String) -> Int {
        let output = ShellCommand.run(gitExecutable, ["-C", clonePath, "diff-index", "--cached", "--name-only", "-z", "HEAD"]) ?? ""
        return output.split(separator: "\0").count
    }

    // Stats every tracked file of a Unity checkout; callers must not run it often or in parallel.
    static func countChangedTrackedFiles(in clonePath: String) -> Int? {
        guard let output = ShellCommand.run(gitExecutable, ["-C", clonePath, "status", "--porcelain=v1", "-z", "--untracked-files=no"]) else { return nil }
        return parseStatusPaths(output).count
    }

    static func filterChangedFiles(in repositoryPath: String, absolutePaths: [String]) -> [String] {
        guard absolutePaths.isEmpty == false,
              let output = ShellCommand.run(gitExecutable, ["-C", repositoryPath, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--"] + absolutePaths) else { return [] }
        return parseStatusPaths(output).map { repositoryPath + "/" + $0 }
    }

    private static func parseStatusPaths(_ porcelainOutput: String) -> [String] {
        var paths: [String] = []
        var isRenameSourceNext = false
        for field in porcelainOutput.split(separator: "\0", omittingEmptySubsequences: true) {
            if isRenameSourceNext {
                isRenameSourceNext = false
                continue
            }

            let status = field.prefix(2)
            paths.append(String(field.dropFirst(3)))
            isRenameSourceNext = status.contains("R") || status.contains("C")
        }
        return paths
    }
}
