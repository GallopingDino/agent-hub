// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "agent-hub",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "agent-hub", path: "Sources/agent-hub")
    ]
)
