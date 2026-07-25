import Foundation

public struct ClaudeCodeLocator: Sendable {
    private let injected: Injected?

    private enum Injected {
        case found(String)
        case notFound
    }

    public init() {
        injected = nil
    }

    init(injectedPath: String?) {
        if let path = injectedPath {
            injected = .found(path)
        } else {
            injected = .notFound
        }
    }

    private static let knownDirs: [String] = [
        "~/.local/bin",
        "~/.claude/local",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.bun/bin",
        "~/.npm-global/bin",
    ]

    public func resolve() -> String? {
        switch injected {
        case let .found(path): return path
        case .notFound: return nil
        case .none: break
        }

        if let pathDirs = pathDirectories() {
            for dir in pathDirs {
                let candidate = (dir as NSString).appendingPathComponent("claude")
                if isExecutable(at: candidate) {
                    return candidate
                }
            }
        }

        for dir in Self.knownDirs {
            let expanded = (dir as NSString).expandingTildeInPath
            let candidate = (expanded as NSString).appendingPathComponent("claude")
            if isExecutable(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Internal helpers

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
