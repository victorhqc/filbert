// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ai-usage",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "Core",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ZAIProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/ZAI",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ClaudeCodeProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/ClaudeCode"
        ),
        .executableTarget(
            name: "App",
            dependencies: ["Core", "ZAIProvider"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "ZAIProviderTests",
            dependencies: ["ZAIProvider"],
            path: "Tests/ZAIProviderTests"
        ),
        .testTarget(
            name: "ClaudeCodeProviderTests",
            dependencies: ["ClaudeCodeProvider"],
            path: "Tests/ClaudeCodeProviderTests"
        ),
    ]
)
