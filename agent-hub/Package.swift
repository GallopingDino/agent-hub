// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "agent-hub",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "agent-hub", path: "Sources/agent-hub"),
        .executableTarget(name: "AgentHubBar", path: "Sources/AgentHubBar")
    ]
)
