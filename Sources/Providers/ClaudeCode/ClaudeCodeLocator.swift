import Foundation

/// Resolves the absolute path to the `claude` binary on this machine
/// (providers 02 AC1). Checks PATH directories first, then a fixed list
/// of known install locations. Never throws — a missing binary returns
/// `nil` rather than an error.
public struct ClaudeCodeLocator: Sendable {
    private let injected: Injected?

    private enum Injected {
        case found(String)
        case notFound
    }

    /// Production initializer — does real filesystem resolution.
    public init() {
        injected = nil
    }

    /// Test-only: returns `path` when given, or `nil` for `.notFound`.
    init(injectedPath: String?) {
        if let path = injectedPath {
            injected = .found(path)
        } else {
            injected = .notFound
        }
    }

    /// Known install directories checked after PATH lookup fails
    /// (providers 02 AC1).
    private static let knownDirs: [String] = [
        "~/.local/bin",
        "~/.claude/local",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.bun/bin",
        "~/.npm-global/bin",
    ]

    /// Returns the absolute path to the first `claude` binary found, or
    /// `nil` when the binary is not installed in any searched location.
    public func resolve() -> String? {
        // Test mode: return the injected value immediately.
        switch injected {
        case let .found(path): return path
        case .notFound: return nil
        case .none: break // fall through to real resolution
        }

        // 1. PATH — resolved via FileManager + /usr/bin/env, not a shell
        //    (providers 02 AC1).
        if let pathDirs = pathDirectories() {
            for dir in pathDirs {
                let candidate = (dir as NSString).appendingPathComponent("claude")
                if isExecutable(at: candidate) {
                    return candidate
                }
            }
        }

        // 2. Known install directories (providers 02 AC1).
        for dir in Self.knownDirs {
            let expanded = (dir as NSString).expandingTildeInPath
            let candidate = (expanded as NSString).appendingPathComponent("claude")
            if isExecutable(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Internal helpers (testable)

    func pathDirectories() -> [String]? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }
        return path.components(separatedBy: ":")
    }

    func isExecutable(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
