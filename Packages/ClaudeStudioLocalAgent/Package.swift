// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudeStudioLocalAgent",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ClaudeStudioLocalAgentCore",
            targets: ["ClaudeStudioLocalAgentCore"]
        ),
        .executable(
            name: "ClaudeStudioLocalAgentHost",
            targets: ["ClaudeStudioLocalAgentHost"]
        ),
    ],
    targets: [
        .target(
            name: "ClaudeStudioLocalAgentCore",
            path: "Sources/ClaudeStudioLocalAgentCore"
        ),
        .executableTarget(
            name: "ClaudeStudioLocalAgentHost",
            dependencies: ["ClaudeStudioLocalAgentCore"],
            path: "Sources/ClaudeStudioLocalAgentHost"
        ),
        .testTarget(
            name: "ClaudeStudioLocalAgentCoreTests",
            dependencies: ["ClaudeStudioLocalAgentCore"],
            path: "Tests/ClaudeStudioLocalAgentCoreTests"
        ),
    ]
)
