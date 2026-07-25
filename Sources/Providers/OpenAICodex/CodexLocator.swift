import Foundation

public struct CodexLocator: Sendable {
    private let environment: [String: String]
    private let isExecutable: @Sendable (String) -> Bool

    public init() {
        self.init(
            environment: ProcessInfo.processInfo.environment,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    init(
        environment: [String: String],
        isExecutable: @escaping @Sendable (String) -> Bool
    ) {
        self.environment = environment
        self.isExecutable = isExecutable
    }

    public func resolve() -> String? {
        for directory in pathDirectories + knownDirectories {
            let candidate = (directory as NSString).appendingPathComponent("codex")
            if isExecutable(candidate) {
                return candidate
            }
        }
        for candidate in desktopAppExecutablePaths where isExecutable(candidate) {
            return candidate
        }
        return nil
    }

    private var pathDirectories: [String] {
        guard let path = environment["PATH"], !path.isEmpty else { return [] }
        return path.split(separator: ":").map(String.init)
    }

    private var knownDirectories: [String] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/Library/pnpm",
            "\(home)/.volta/bin",
            "\(home)/.asdf/shims",
            "\(home)/.yarn/bin",
            "\(home)/Library/Application Support/Codex/bin",
        ]
    }

    private var desktopAppExecutablePaths: [String] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/MacOS/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/MacOS/codex",
        ]
    }
}
