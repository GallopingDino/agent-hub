import Foundation

struct AgentLastMessage {
    private static let changedFilesMarker = "Изменённые файлы:"

    let text: String
    let reportedFiles: [String]

    init(text: String) {
        self.text = text
        reportedFiles = Self.parseReportedFiles(text)
    }

    private static func parseReportedFiles(_ text: String) -> [String] {
        guard let markerRange = text.range(of: changedFilesMarker, options: .backwards) else { return [] }

        var files: [String] = []
        for rawLine in text[markerRange.upperBound...].split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            if line.hasPrefix("```") || line.isEmpty { continue }
            guard line.contains("/") || line.contains("."), line.contains(" ") == false else { break }
            files.append(stripLineSuffix(line))
        }
        return files
    }

    private static func stripLineSuffix(_ path: String) -> String {
        guard let colon = path.lastIndex(of: ":"),
              path[path.index(after: colon)...].allSatisfy(\.isNumber),
              path.index(after: colon) < path.endIndex else { return path }
        return String(path[..<colon])
    }
}
