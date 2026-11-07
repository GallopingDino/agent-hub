import AppKit
import Foundation

enum SessionCloser {
    private static let exitWaitSeconds: TimeInterval = 3

    // Returns nil on success, otherwise what could not be closed.
    static func close(_ session: AgentSession, isClosingProject: Bool) -> String? {
        let reply = AgentTabsClient.closeTab(ofProcess: session.pid)
        guard reply.ok else { return reply.error ?? "could not close the terminal tab" }
        guard isClosingProject else { return nil }

        // The IDE records the agents it had open while closing, to resume them later; this one must be gone by then.
        waitForExit(session.pid)
        var failures: [String] = []
        if let project = session.riderProject, IdeIntegrations.closeProject(directory: project) == false {
            failures.append("could not close the IDE window")
        }
        if let unityPid = session.unityPid, NSRunningApplication(processIdentifier: unityPid)?.terminate() != true {
            failures.append("could not quit the Unity editor")
        }
        return failures.isEmpty ? nil : failures.joined(separator: "; ")
    }

    private static func waitForExit(_ pid: Int32) {
        let deadline = Date().addingTimeInterval(exitWaitSeconds)
        while kill(pid, 0) == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
