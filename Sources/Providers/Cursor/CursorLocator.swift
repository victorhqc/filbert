import Foundation

/// Resolves the user's Cursor CLI binary without invoking a shell
/// (providers 07 AC4b).
///
/// Mirrors `CodexLocator` (providers 05 AC1): lookup order is the process
/// `PATH`, then known macOS install locations (Homebrew, `/usr/local/bin`,
/// the Cursor desktop app's bundled CLI). A missing CLI is a normal setup
/// state, not an error.
public struct CursorLocator: Sendable {
    private let environment: [String: String]
    private let isExecutable: @Sendable (String) -> Bool

    /// Uses the process environment and filesystem for production lookup.
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

    /// Returns the absolute path to the first executable `cursor-agent` /
    /// `cursor` / `agent` binary found through `PATH`, then known macOS
    /// install locations, then the Cursor desktop app's bundled CLI.
    /// Returns `nil` when no executable is found — never throws.
    public func resolve() -> String? {
        let names = ["cursor-agent", "cursor", "agent"]
        for directory in pathDirectories + knownDirectories {
            for name in names {
                let candidate = (directory as NSString).appendingPathComponent(name)
                if isExecutable(candidate) {
                    return candidate
                }
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
        ]
    }

    private var desktopAppExecutablePaths: [String] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return [
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor-agent",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
            "\(home)/Applications/Cursor.app/Contents/Resources/app/bin/cursor-agent",
            "\(home)/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        ]
    }
}
