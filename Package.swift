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
            path: "Sources/Providers/ClaudeCode",
            resources: [.process("Resources")]
        ),
        .target(
            name: "DeepSeekProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/DeepSeek",
            resources: [.process("Resources")]
        ),
        .target(
            name: "OpenAICodexProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/OpenAICodex"
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                "ZAIProvider",
                "ClaudeCodeProvider",
                "DeepSeekProvider",
                "OpenAICodexProvider",
            ],
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
        .testTarget(
            name: "DeepSeekProviderTests",
            dependencies: ["DeepSeekProvider"],
            path: "Tests/DeepSeekProviderTests"
        ),
        .testTarget(
            name: "OpenAICodexProviderTests",
            dependencies: ["OpenAICodexProvider"],
            path: "Tests/OpenAICodexProviderTests"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"],
            path: "Tests/AppTests"
        ),
    ]
)
