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
            "\(miseDataDirectory)/shims",
            "\(home)/Library/Application Support/Codex/bin",
        ]
    }

    /// mise stores its shims under `$MISE_DATA_DIR` (or `$XDG_DATA_HOME/mise`,
    /// defaulting to `~/.local/share/mise`). Matches how GUI-launched apps miss
    /// the shell `PATH` that would normally expose the shim directory.
    private var miseDataDirectory: String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        if let miseDataDir = environment["MISE_DATA_DIR"], !miseDataDir.isEmpty {
            return miseDataDir
        }
        if let xdgDataHome = environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            return "\(xdgDataHome)/mise"
        }
        return "\(home)/.local/share/mise"
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
