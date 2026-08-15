// swift-tools-version: 5.9
import PackageDescription

/// Strict type-checking for every `Sources/` target: warnings are errors and
/// complete concurrency checking is on (ci 04 AC1, AC2). Test targets are
/// exempt — a warning in a test must not fail the gate. `.unsafeFlags` is the
/// only SPM-supported knob for these flags at swift-tools-version 5.9; the
/// flags are pinned at the build-config level so no contributor can opt out by
/// accident.
let strictSourceSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-warnings-as-errors",
        "-strict-concurrency=complete",
    ]),
]

let package = Package(
    name: "filbert",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "Core",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .target(
            name: "ZAIProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/ZAI",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .target(
            name: "ClaudeCodeProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/ClaudeCode",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .target(
            name: "DeepSeekProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/DeepSeek",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .target(
            name: "OpenAICodexProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/OpenAICodex",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .target(
            name: "OpenCodeGoProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/OpenCodeGo",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .target(
            name: "CursorProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/Cursor",
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                "ZAIProvider",
                "ClaudeCodeProvider",
                "DeepSeekProvider",
                "OpenAICodexProvider",
                "OpenCodeGoProvider",
                "CursorProvider",
            ],
            resources: [.process("Resources")],
            swiftSettings: strictSourceSettings
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
            name: "OpenCodeGoProviderTests",
            dependencies: ["OpenCodeGoProvider"],
            path: "Tests/OpenCodeGoProviderTests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "CursorProviderTests",
            dependencies: ["CursorProvider"],
            path: "Tests/CursorProviderTests"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"],
            path: "Tests/AppTests"
        ),
    ]
)
