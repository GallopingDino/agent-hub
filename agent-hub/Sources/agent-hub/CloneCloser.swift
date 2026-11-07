import AppKit
import Foundation

enum CloneCloser {
    // Returns nil on success, otherwise what could not be closed.
    static func close(_ clone: CloneState) -> String? {
        var failures: [String] = []
        if clone.isOpenInRider, IdeIntegrations.closeProject(directory: clone.path) == false {
            failures.append("could not close the IDE window")
        }
        if let unityPid = clone.unityPid, NSRunningApplication(processIdentifier: unityPid)?.terminate() != true {
            failures.append("could not quit the Unity editor")
        }
        return failures.isEmpty ? nil : "\(clone.name): " + failures.joined(separator: "; ")
    }
}
