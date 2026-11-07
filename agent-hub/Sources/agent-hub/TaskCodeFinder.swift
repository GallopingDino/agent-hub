import Foundation

// Task trackers such as Asana give tasks a project prefix and a number, like BR-1566; teams put it in branch and session names.
enum TaskCodeFinder {
    private static let codePattern = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9])([A-Za-z][A-Za-z0-9]{1,7})-([0-9]{1,7})(?![0-9])")
    // Look like codes but are names of standards.
    private static let notTaskPrefixes: Set<String> = ["ISO", "UTF", "RFC", "SHA", "MD5", "X86"]

    // The session name is the user's own word on the task, so it wins over the branch.
    static func find(sessionName: String?, branch: String?) -> String? {
        [sessionName, branch].compactMap { $0 }.lazy.compactMap(findCode).first
    }

    private static func findCode(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for match in codePattern.matches(in: text, range: range) {
            guard let prefixRange = Range(match.range(at: 1), in: text), let numberRange = Range(match.range(at: 2), in: text) else { continue }
            let prefix = text[prefixRange].uppercased()
            if notTaskPrefixes.contains(prefix) { continue }
            return "\(prefix)-\(text[numberRange])"
        }
        return nil
    }
}
