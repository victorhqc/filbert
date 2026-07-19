// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ai-usage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(
            name: "ZAIProvider",
            dependencies: ["Core"],
            path: "Sources/Providers/ZAI"
        ),
        .executableTarget(
            name: "App",
            dependencies: ["Core", "ZAIProvider"]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        ),
    ]
)
