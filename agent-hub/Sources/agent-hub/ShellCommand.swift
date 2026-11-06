import ChildProcess
import Foundation

enum ShellCommand {
    static func run(_ executable: String, _ arguments: [String]) -> String? {
        guard let result = ChildProcess.run(executable, arguments), result.isSuccess else { return nil }
        return String(decoding: result.output, as: UTF8.self)
    }
}
