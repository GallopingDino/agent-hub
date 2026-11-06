import Foundation

enum UnityEditorActivator {
    // A background command-line process may not activate another app on macOS 14+, so ask System Events to do it.
    static func activate(pid: Int32) -> Bool {
        let script = "tell application \"System Events\" to set frontmost of (first process whose unix id is \(pid)) to true"
        return ShellCommand.run("/usr/bin/osascript", ["-e", script]) != nil
    }
}
