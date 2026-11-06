// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "agent-hub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ChildProcess", path: "Sources/ChildProcess"),
        .executableTarget(name: "agent-hub", dependencies: ["ChildProcess"], path: "Sources/agent-hub"),
        .executableTarget(name: "AgentHubBar", dependencies: ["ChildProcess"], path: "Sources/AgentHubBar")
    ]
)
