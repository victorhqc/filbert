import Core
import Foundation

// MARK: - Paths (providers 02 Plan §5)

/// `~/.claude/filbert-statusline` — the compiled helper binary
/// (providers 02 Plan §5).
public let claudeHelperDestURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude")
    .appendingPathComponent("filbert-statusline")

/// `~/.claude/settings.json` — Claude Code's settings file
/// (providers 02 AC8).
public let claudeSettingsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude")
    .appendingPathComponent("settings.json")

// MARK: - Installer error (providers 02 AC8)

public enum InstallerError: Error, Equatable, Sendable {
    /// `swiftc` is not on PATH — install cannot proceed (providers 02 Plan §5).
    case swiftcNotFound
    /// `swiftc` exited non-zero.
    case compilationFailed(Int32)
    /// `settings.json` exists but does not parse as JSON (providers 02 AC8).
    case unparseableSettings
    /// The bundled helper source is missing from the app resources.
    case helperSourceNotFound
    /// The helper or Claude settings did not match the staged installation.
    case configurationVerificationFailed

    public static func == (lhs: InstallerError, rhs: InstallerError) -> Bool {
        switch (lhs, rhs) {
        case (.swiftcNotFound, .swiftcNotFound): true
        case (.unparseableSettings, .unparseableSettings): true
        case (.helperSourceNotFound, .helperSourceNotFound): true
        case (.configurationVerificationFailed, .configurationVerificationFailed): true
        case let (.compilationFailed(lhsCode), .compilationFailed(rhsCode)): lhsCode == rhsCode
        default: false
        }
    }
}

extension InstallerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .swiftcNotFound:
            String(localized: "Swift compiler not found. Install Xcode Command Line Tools.")
        case let .compilationFailed(code):
            String(localized: "Helper compilation failed with exit code \(code).")
        case .unparseableSettings:
            String(localized: "Could not parse ~/.claude/settings.json.")
        case .helperSourceNotFound:
            String(localized: "Helper source file not found in app bundle.")
        case .configurationVerificationFailed:
            String(localized: "Could not verify the helper installation.")
        }
    }
}

// MARK: - Codable model for ~/.claude/settings.json (ci 04 AC7)

//
// `settings.json` is user-owned and open-schema: Claude Code accepts arbitrary
// sibling keys alongside `statusLine`, and `statusLine` itself may be a bare
// string or an object with arbitrary keys (`padding`, `refreshInterval`, …).
// These types model the known keys (`statusLine`, `command`, `type`) while
// sinking every unknown key into an `extra: [String: AnyJSON]` so a
// read/modify/write round-trip preserves them — without exposing the `Any`
// type (ci 04 AC5/AC6). `AnyJSON` is the open-schema value type from `Core`.

/// The `statusLine` value: either a bare command string or a typed object
/// (providers 02 AC8).
enum StatusLineValue: Equatable {
    case string(String)
    case object(StatusLineObject)
}

/// The object form of `statusLine`. `command` and `type` are typed; every
/// other key (`padding`, `refreshInterval`, …) is preserved in `extra`.
struct StatusLineObject: Equatable {
    var command: String?
    var type: String?
    var extra: [String: AnyJSON]

    init(command: String? = nil, type: String? = nil, extra: [String: AnyJSON] = [:]) {
        self.command = command
        self.type = type
        self.extra = extra
    }
}

/// The top-level `~/.claude/settings.json` object. `statusLine` is typed;
/// every other top-level key is preserved in `extra`.
struct ClaudeSettings: Equatable {
    var statusLine: StatusLineValue?
    var extra: [String: AnyJSON]

    init(statusLine: StatusLineValue? = nil, extra: [String: AnyJSON] = [:]) {
        self.statusLine = statusLine
        self.extra = extra
    }
}

// MARK: - Codable round-trip via [String: AnyJSON]

//
// `KeyedDecodingContainer` with a fixed `CodingKey` enum silently drops keys
// not in the enum, which would lose exactly the open-schema sibling keys this
// model exists to preserve. Decoding the whole object as `[String: AnyJSON]`
// and extracting known keys by hand keeps every key — known ones become typed
// fields, the rest land in `extra`.

extension ClaudeSettings: Codable {
    private static let statusLineKey = "statusLine"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: AnyJSON].self)
        if let value = raw[Self.statusLineKey] {
            statusLine = try Self.decodeStatusLine(value)
        } else {
            statusLine = nil
        }
        extra = raw.filter { $0.key != Self.statusLineKey }
    }

    func encode(to encoder: Encoder) throws {
        var raw = extra
        if let statusLine {
            raw[Self.statusLineKey] = Self.encodeStatusLine(statusLine)
        }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    private static func decodeStatusLine(_ value: AnyJSON) throws -> StatusLineValue {
        switch value {
        case let .string(string):
            return .string(string)
        case let .object(dict):
            return try .object(Self.decodeStatusLineObject(dict))
        case .null, .bool, .number, .array:
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "statusLine must be a string or an object"
            ))
        }
    }

    private static func decodeStatusLineObject(_ dict: [String: AnyJSON]) throws -> StatusLineObject {
        var object = StatusLineObject()
        var extra = dict
        if let command = extra.removeValue(forKey: "command") {
            object.command = Self.stringValue(command)
        }
        if let type = extra.removeValue(forKey: "type") {
            object.type = Self.stringValue(type)
        }
        object.extra = extra
        return object
    }

    private static func encodeStatusLine(_ value: StatusLineValue) -> AnyJSON {
        switch value {
        case let .string(string):
            .string(string)
        case let .object(object):
            .object(Self.encodeStatusLineObject(object))
        }
    }

    private static func encodeStatusLineObject(_ object: StatusLineObject) -> [String: AnyJSON] {
        var raw = object.extra
        if let command = object.command {
            raw["command"] = .string(command)
        }
        if let type = object.type {
            raw["type"] = .string(type)
        }
        return raw
    }

    /// Pulls a `String` out of an `AnyJSON` that is expected to hold a string,
    /// returning `nil` for any other kind (matches the historical
    /// `as? String` tolerance).
    private static func stringValue(_ value: AnyJSON) -> String? {
        if case let .string(string) = value {
            return string
        }
        return nil
    }
}

// MARK: - Installer (providers 02 AC7, AC8, AC11)

/// Manages installation and removal of the statusline helper binary and its
/// integration into Claude Code's `~/.claude/settings.json`.
///
/// The helper binary reads statusline JSON from stdin, extracts
/// `rate_limits`, and writes an atomic cache file for the provider to read
/// (providers 02 AC7). The installer chains the helper into any existing
/// `statusLine.command` so the user's prior statusline continues to work
/// (providers 02 AC8).
public struct StatuslineHelperInstaller: Sendable {
    private let settingsURL: URL
    private let helperDestURL: URL
    private let cacheURL: URL
    private let legacyConfiguration: LegacyClaudeBrandConfiguration?
    private let swiftCompilerPath: String?

    // MARK: - Chain markers

    /// Sentinels embedded in the chained shell command so we can detect our
    /// own wrapper and extract the original command (providers 02 AC8).
    private static let chainStart = "###FILBERT-CHAIN-START###"
    private static let chainSep = "###FILBERT-CHAIN-SEPARATOR###"

    // MARK: - Init

    public init() {
        self.init(
            settingsURL: claudeSettingsFileURL,
            helperDestURL: claudeHelperDestURL,
            cacheURL: claudeCodeCacheFileURL,
            legacyConfiguration: .production,
            swiftCompilerPath: nil
        )
    }

    public init(
        settingsURL: URL,
        helperDestURL: URL,
        cacheURL: URL
    ) {
        self.init(
            settingsURL: settingsURL,
            helperDestURL: helperDestURL,
            cacheURL: cacheURL,
            legacyConfiguration: nil,
            swiftCompilerPath: nil
        )
    }

    init(
        settingsURL: URL,
        helperDestURL: URL,
        cacheURL: URL,
        legacyConfiguration: LegacyClaudeBrandConfiguration?,
        swiftCompilerPath: String?
    ) {
        self.settingsURL = settingsURL
        self.helperDestURL = helperDestURL
        self.cacheURL = cacheURL
        self.legacyConfiguration = legacyConfiguration
        self.swiftCompilerPath = swiftCompilerPath
    }

    // MARK: - Status (providers 02 AC3)

    /// Returns `true` when the compiled helper binary exists and is
    /// executable at the expected destination.
    public func isHelperInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: helperDestURL.path)
    }

    func hasLegacyHelperInstallation() -> Bool {
        (try? hasLegacyHelperIntegration()) == true
    }

    // MARK: - Install (providers 02 AC7, AC8)

    /// Full install: compiles the helper from the bundled Swift source,
    /// then chains it into `~/.claude/settings.json`.
    ///
    /// - Parameter helperSourceURL: The URL of `statusline_helper.swift` in
    ///   the app bundle. Obtain via `Bundle.module.url(forResource:withExtension:)`.
    public func install(helperSourceURL: URL) throws {
        let helperExisted = isHelperInstalled()
        let settingsBackup = try? Data(contentsOf: settingsURL)
        do {
            try compileHelper(sourceURL: helperSourceURL)
            try updateSettingsForInstall()
            try verifyInstalledConfiguration()
            try migrateLegacyCacheIfNeeded()
            removeLegacyArtifacts()
        } catch {
            if !helperExisted {
                try? FileManager.default.removeItem(at: helperDestURL)
            }
            restoreSettings(from: settingsBackup)
            throw error
        }
    }

    func migrateLegacyInstallationIfNeeded(helperSourceURL: URL) throws -> Bool {
        guard try hasLegacyHelperIntegration() else {
            try migrateLegacyCacheIfNeeded()
            return false
        }
        try install(helperSourceURL: helperSourceURL)
        return true
    }

    // MARK: - Uninstall (providers 02 AC11)

    /// Removes the helper binary, unwraps any filbert chain from
    /// `settings.json`, and deletes the cache file.
    public func uninstall() throws {
        // 1. Unwrap settings.json (providers 02 AC11).
        try removeFromSettings()

        // 2. Delete the compiled helper binary.
        try? FileManager.default.removeItem(at: helperDestURL)

        // 3. Delete the cache file so stale data doesn't linger.
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Internal (testable entry points)

    /// Settings-only install. Assumes the helper binary already exists at
    /// `helperDestURL`. Exposed for testing so suites can pre-seed a dummy
    /// binary and exercise the settings-manipulation logic in isolation.
    func installSettingsOnly() throws {
        try updateSettingsForInstall()
    }

    /// Settings-only uninstall. Exposed for testing so suites can verify
    /// chain unwrapping without touching the filesystem for the binary.
    func uninstallSettingsOnly() throws {
        try removeFromSettings()
    }

    // MARK: - Compilation (providers 02 Plan §5)

    private func compileHelper(sourceURL: URL) throws {
        let destDir = helperDestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destDir,
            withIntermediateDirectories: true
        )

        guard let swiftcPath = findSwiftC() else {
            throw InstallerError.swiftcNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftcPath)
        process.arguments = ["-O", "-o", helperDestURL.path, sourceURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InstallerError.compilationFailed(process.terminationStatus)
        }
    }

    private func findSwiftC() -> String? {
        if let swiftCompilerPath {
            return swiftCompilerPath
        }
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }
        for dir in pathEnv.components(separatedBy: ":") {
            let candidate = (dir as NSString).appendingPathComponent("swiftc")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Settings I/O

    /// Reads `settingsURL` as a `ClaudeSettings` model, or returns `nil` when
    /// the file is absent. Throws `InstallerError.unparseableSettings` when the
    /// file exists but is not valid JSON (providers 02 AC8).
    private func readSettings() throws -> ClaudeSettings? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: settingsURL)
        do {
            return try JSONDecoder().decode(ClaudeSettings.self, from: data)
        } catch {
            throw InstallerError.unparseableSettings
        }
    }

    private func writeSettings(_ settings: ClaudeSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    private func restoreSettings(from backup: Data?) {
        if let backup {
            try? backup.write(to: settingsURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: settingsURL)
        }
    }

    // MARK: - Settings manipulation (providers 02 AC8)

    /// Extracts the `command` string from a `statusLine` value, which may
    /// be a plain string or a `{"command": "..."}` object (providers 02 AC8).
    private func commandFromStatusLine(_ value: StatusLineValue?) -> String? {
        switch value {
        case let .string(string):
            string
        case let .object(object):
            object.command
        case .none:
            nil
        }
    }

    private func updateSettingsForInstall() throws {
        var settings = try readSettings() ?? ClaudeSettings()
        // Preserve any existing statusLine keys (padding, refreshInterval, ...)
        // so we only rewrite `command` and ensure `type` is set.
        var statusLineObject = existingStatusLineObject(settings.statusLine) ?? StatusLineObject()
        let existingCommand = commandFromStatusLine(settings.statusLine)

        let newCommand: String

        if let existingCommand {
            let legacyChain = legacyConfiguration.map {
                existingCommand.contains($0.chainStart)
            } ?? false
            let legacySoleHelper = legacyConfiguration.map {
                existingCommand == $0.helperURL.path
            } ?? false
            if existingCommand.contains(Self.chainStart) {
                // Already chained by us — extract original, re-wrap so a
                // reinstall replaces our wrapper in place (providers 02 AC8).
                let original = extractOriginalCommand(from: existingCommand) ?? ""
                newCommand = wrapCommand(original, helperPath: helperDestURL.path)
            } else if legacyChain, let legacyConfiguration {
                let original = extractOriginalCommand(
                    from: existingCommand,
                    chainStart: legacyConfiguration.chainStart,
                    chainSeparator: legacyConfiguration.chainSeparator
                ) ?? ""
                newCommand = wrapCommand(original, helperPath: helperDestURL.path)
            } else if legacySoleHelper {
                newCommand = helperDestURL.path
            } else {
                // User's own command — chain our helper after it
                // (providers 02 AC8).
                newCommand = wrapCommand(existingCommand, helperPath: helperDestURL.path)
            }
        } else {
            // No prior statusLine — set our helper as the sole command.
            newCommand = helperDestURL.path
        }

        // Claude Code requires `type: "command"` to invoke the statusLine
        // (https://code.claude.com/docs/en/statusline). Always set it on
        // install so the helper is actually spawned.
        statusLineObject.type = "command"
        statusLineObject.command = newCommand
        settings.statusLine = .object(statusLineObject)
        try writeSettings(settings)
    }

    /// Returns the existing `statusLine` as an object if it is one, so sibling
    /// keys (`padding`, `refreshInterval`, …) survive the install rewrite. A
    /// bare-string `statusLine` yields `nil` here — install normalizes it to
    /// the object form (providers 02 AC8).
    private func existingStatusLineObject(_ value: StatusLineValue?) -> StatusLineObject? {
        if case let .object(object) = value {
            return object
        }
        return nil
    }

    private func removeFromSettings() throws {
        guard var mutable = try? readSettings() else { return }

        guard let command = commandFromStatusLine(mutable.statusLine) else {
            return
        }

        if command.contains(Self.chainStart) {
            // Our wrapper is present — extract the original command and
            // restore it (providers 02 AC11). Like the original implementation,
            // restore as a bare object with only `command`; sibling keys are
            // not re-added (byte-equivalence with the prior behaviour, ci 04 AC7).
            let original = extractOriginalCommand(from: command) ?? ""
            if original.isEmpty {
                mutable.statusLine = nil
            } else {
                mutable.statusLine = .object(StatusLineObject(command: original))
            }
        } else if command == helperDestURL.path {
            // Our helper is the only command — remove the statusLine key
            // entirely (providers 02 AC11).
            mutable.statusLine = nil
        }
        // else: a different command, not ours — leave it alone.

        try writeSettings(mutable)
    }

    // MARK: - Chain helpers (providers 02 AC8)

    /// Wraps an existing command so it runs first, followed by the helper
    /// reading the same stdin. The shell pipeline captures stdin into a
    /// variable, pipes it to the original command, then pipes it to our
    /// helper (whose output is discarded — it writes the cache directly).
    ///
    /// Sentinels `chainStart` / `chainSep` bracket the original command
    /// so we can detect and extract it on reinstall or uninstall
    /// (providers 02 AC8).
    private func wrapCommand(_ original: String, helperPath: String) -> String {
        let escaped = escapeForShell(original)
        return "bash -c \"INPUT=$(cat); "
            + "echo \\\"$INPUT\\\" | "
            + "\(Self.chainStart)\(escaped)\(Self.chainSep); "
            + "echo \\\"$INPUT\\\" | \(helperPath) > /dev/null\""
    }

    /// Extracts the original user command from between the chain sentinels
    /// and unescapes shell-escaped characters so the round-trip is lossless
    /// (providers 02 AC8, AC11).
    private func extractOriginalCommand(from wrapped: String) -> String? {
        extractOriginalCommand(
            from: wrapped,
            chainStart: Self.chainStart,
            chainSeparator: Self.chainSep
        )
    }

    private func extractOriginalCommand(
        from wrapped: String,
        chainStart: String,
        chainSeparator: String
    ) -> String? {
        guard let startRange = wrapped.range(of: chainStart) else {
            return nil
        }
        let searchRange = startRange.upperBound ..< wrapped.endIndex
        guard let sepRange = wrapped.range(of: chainSeparator, range: searchRange) else {
            return nil
        }
        let escaped = String(wrapped[startRange.upperBound ..< sepRange.lowerBound])
        let original = unescapeFromShell(escaped)
        return original.isEmpty ? nil : original
    }

    /// Escapes characters that would break the double-quoted shell string
    /// the original command is embedded in.
    private func escapeForShell(_ input: String) -> String {
        input.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    /// Reverses `escapeForShell` so the original command is restored
    /// losslessly on uninstall (providers 02 AC11).
    private func unescapeFromShell(_ input: String) -> String {
        var result = ""
        var index = input.startIndex
        while index < input.endIndex {
            let isBackslash = input[index] == "\\"
            let nextIdx = input.index(after: index)
            if isBackslash, nextIdx < input.endIndex {
                result.append(input[nextIdx])
                index = input.index(after: nextIdx)
            } else {
                result.append(input[index])
                index = nextIdx
            }
        }
        return result
    }

    private func hasLegacyHelperIntegration() throws -> Bool {
        guard let legacyConfiguration else {
            return false
        }
        if FileManager.default.isExecutableFile(atPath: legacyConfiguration.helperURL.path) {
            return true
        }
        guard let command = try commandFromStatusLine(readSettings()?.statusLine) else {
            return false
        }
        return command == legacyConfiguration.helperURL.path
            || command.contains(legacyConfiguration.chainStart)
    }

    private func verifyInstalledConfiguration() throws {
        guard isHelperInstalled(),
              let command = try commandFromStatusLine(readSettings()?.statusLine),
              command.contains(helperDestURL.path)
        else {
            throw InstallerError.configurationVerificationFailed
        }
    }

    private func migrateLegacyCacheIfNeeded() throws {
        guard let legacyConfiguration else {
            return
        }
        guard !FileManager.default.fileExists(atPath: cacheURL.path) else {
            return
        }
        let legacyStore = StatuslineCacheStore(cacheURL: legacyConfiguration.cacheURL)
        guard let cache = legacyStore.read() else {
            return
        }
        let currentStore = StatuslineCacheStore(cacheURL: cacheURL)
        try currentStore.write(cache)
        guard currentStore.read() != nil else {
            throw InstallerError.configurationVerificationFailed
        }
        try? FileManager.default.removeItem(at: legacyConfiguration.cacheURL)
    }

    private func removeLegacyArtifacts() {
        guard let legacyConfiguration else {
            return
        }
        try? FileManager.default.removeItem(at: legacyConfiguration.helperURL)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.removeItem(at: legacyConfiguration.cacheURL)
        }
    }
}
