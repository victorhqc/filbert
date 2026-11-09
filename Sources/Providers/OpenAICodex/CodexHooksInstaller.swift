import Core
import Foundation

public enum CodexHooksError: Error, Equatable, Sendable {
    case unreadableHooksFile(path: String)
    case unrecognizedHooksFile(path: String)
}

extension CodexHooksError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unreadableHooksFile(path), let .unrecognizedHooksFile(path):
            String(
                displayLocalized: """
                Filbert can't update \(path) because it isn't a hooks file Filbert recognizes. \
                The file was not changed.
                """,
                bundle: .module
            )
        }
    }
}

extension CodexHooksError: DiagnosticError {
    public var diagnosticCode: String {
        switch self {
        case .unreadableHooksFile: "hooks-file-unreadable"
        case .unrecognizedHooksFile: "hooks-file-unrecognized"
        }
    }
}

/// Edits only Filbert's own handlers in Codex's user hooks file. Codex skips
/// a new or changed hook until the user trusts it, so the command must never
/// change between Filbert versions.
struct CodexHooksInstaller: Sendable {
    static let events = ["UserPromptSubmit", "Stop", "PostModelRequest", "PostToolUse"]
    static let timeoutSeconds = 5

    let hooksURL: URL
    let signalURL: URL

    static let production = CodexHooksInstaller(
        hooksURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("hooks.json"),
        signalURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("filbert")
            .appendingPathComponent("codex-activity")
    )

    var command: String {
        "/usr/bin/touch '\(signalURL.path.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }

    func install() throws {
        var root = try readRoot() ?? [:]
        var hooks = try hooksTable(in: root)
        var changed = false
        for event in Self.events {
            var groups = try groups(for: event, in: hooks)
            guard !containsFilbertHandler(groups) else { continue }
            groups.append(["hooks": .array([.object(filbertHandler)])])
            hooks[event] = .array(groups.map(AnyJSON.object))
            changed = true
        }
        if changed {
            root["hooks"] = .object(hooks)
            try write(root)
        }
        try FileManager.default.createDirectory(
            at: signalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try removeSignalFile()
    }

    func remove() throws {
        if var root = try readRoot() {
            var hooks = try hooksTable(in: root)
            var changed = false
            for event in Self.events {
                let (remaining, removed) = try removingFilbertHandlers(from: groups(for: event, in: hooks))
                guard removed else { continue }
                hooks[event] = remaining.isEmpty ? nil : .array(remaining.map(AnyJSON.object))
                changed = true
            }
            if changed {
                root["hooks"] = hooks.isEmpty ? nil : .object(hooks)
                if root.isEmpty {
                    try FileManager.default.removeItem(at: hooksURL)
                } else {
                    try write(root)
                }
            }
        }
        try removeSignalFile()
    }

    func status() -> ActivitySignalStatus {
        do {
            guard let root = try readRoot() else { return .notInstalled(Self.installDescription) }
            let hooks = try hooksTable(in: root)
            for event in Self.events {
                guard try containsFilbertHandler(groups(for: event, in: hooks)) else {
                    return .notInstalled(Self.installDescription)
                }
            }
        } catch {
            return .notInstalled(DisplayText(describing: error))
        }
        guard FileManager.default.fileExists(atPath: signalURL.path) else {
            return .awaitingFirstSignal(Self.nextSteps)
        }
        return .active
    }

    private static let installDescription = DisplayText {
        String(
            displayLocalized: """
            Install adds Filbert's hooks to ~/.codex/hooks.json. Each hook only updates a file in ~/.cache/filbert. \
            Filbert does not read your prompts or send anything.
            """,
            bundle: .module
        )
    }

    private static let nextSteps = DisplayText {
        String(
            displayLocalized: """
            Codex runs new hooks only after you approve them.
            1. In the Codex CLI, type /hooks and trust all Filbert hooks. In the Codex app, use Settings > Hooks.
            2. Send any prompt in Codex. Activity detection turns on after that.
            You approve once for every app on this Mac that uses Codex, such as the CLI, the Codex app, and other tools. \
            If hooks are turned off in ~/.codex/config.toml, turn them on first.
            """,
            bundle: .module
        )
    }

    private var filbertHandler: [String: AnyJSON] {
        [
            "type": .string("command"),
            "command": .string(command),
            "async": .bool(true),
            "timeout": .number(Double(Self.timeoutSeconds)),
        ]
    }

    private func readRoot() throws -> [String: AnyJSON]? {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: hooksURL)
        } catch {
            throw CodexHooksError.unreadableHooksFile(path: hooksURL.path)
        }
        if String(bytes: data, encoding: .utf8)?.allSatisfy(\.isWhitespace) == true {
            return [:]
        }
        let value: AnyJSON
        do {
            value = try JSONDecoder().decode(AnyJSON.self, from: data)
        } catch {
            throw CodexHooksError.unreadableHooksFile(path: hooksURL.path)
        }
        guard case let .object(root) = value else {
            throw CodexHooksError.unrecognizedHooksFile(path: hooksURL.path)
        }
        return root
    }

    private func hooksTable(in root: [String: AnyJSON]) throws -> [String: AnyJSON] {
        switch root["hooks"] {
        case .none:
            return [:]
        case let .object(hooks):
            return hooks
        default:
            throw CodexHooksError.unrecognizedHooksFile(path: hooksURL.path)
        }
    }

    private func groups(for event: String, in hooks: [String: AnyJSON]) throws -> [[String: AnyJSON]] {
        guard let value = hooks[event] else { return [] }
        guard case let .array(items) = value else {
            throw CodexHooksError.unrecognizedHooksFile(path: hooksURL.path)
        }
        return try items.map { item in
            guard case let .object(group) = item, isRecognizedHandlerList(group["hooks"]) else {
                throw CodexHooksError.unrecognizedHooksFile(path: hooksURL.path)
            }
            return group
        }
    }

    private func isRecognizedHandlerList(_ value: AnyJSON?) -> Bool {
        switch value {
        case .none:
            true
        case let .array(items):
            items.allSatisfy { item in
                if case .object = item {
                    return true
                }
                return false
            }
        default:
            false
        }
    }

    private func containsFilbertHandler(_ groups: [[String: AnyJSON]]) -> Bool {
        groups.contains { group in
            handlers(in: group).contains(where: isFilbertHandler)
        }
    }

    private func removingFilbertHandlers(
        from groups: [[String: AnyJSON]]
    ) -> (remaining: [[String: AnyJSON]], removed: Bool) {
        var removed = false
        let remaining = groups.compactMap { group -> [String: AnyJSON]? in
            let handlers = handlers(in: group)
            let kept = handlers.filter { !isFilbertHandler($0) }
            guard kept.count != handlers.count else { return group }
            removed = true
            guard !kept.isEmpty else { return nil }
            var trimmed = group
            trimmed["hooks"] = .array(kept.map(AnyJSON.object))
            return trimmed
        }
        return (remaining, removed)
    }

    private func handlers(in group: [String: AnyJSON]) -> [[String: AnyJSON]] {
        guard case let .array(items) = group["hooks"] else { return [] }
        return items.compactMap { item in
            guard case let .object(handler) = item else { return nil }
            return handler
        }
    }

    private func isFilbertHandler(_ handler: [String: AnyJSON]) -> Bool {
        handler["command"] == .string(command)
    }

    private func write(_ root: [String: AnyJSON]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(root)
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: hooksURL, options: .atomic)
    }

    private func removeSignalFile() throws {
        guard FileManager.default.fileExists(atPath: signalURL.path) else { return }
        try FileManager.default.removeItem(at: signalURL)
    }
}
