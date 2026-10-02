import Core
import Foundation

public struct StatuslineHelperInstaller: Sendable {
    private let settingsURL: URL
    private let helperDestURL: URL
    private let cacheURL: URL
    private let legacyConfiguration: LegacyClaudeBrandConfiguration?
    private let errorLog: ErrorLog

    private static let chainStart = "###FILBERT-CHAIN-START###"
    private static let chainSep = "###FILBERT-CHAIN-SEPARATOR###"
    private static let originalMarker = "###FILBERT-ORIGINAL:"

    public init() {
        self.init(
            settingsURL: claudeSettingsFileURL,
            helperDestURL: claudeHelperDestURL,
            cacheURL: claudeCodeCacheFileURL,
            legacyConfiguration: .production,
            errorLog: .shared
        )
    }

    public init(
        settingsURL: URL,
        helperDestURL: URL,
        cacheURL: URL,
        errorLog: ErrorLog = .shared
    ) {
        self.init(
            settingsURL: settingsURL,
            helperDestURL: helperDestURL,
            cacheURL: cacheURL,
            legacyConfiguration: nil,
            errorLog: errorLog
        )
    }

    init(
        settingsURL: URL,
        helperDestURL: URL,
        cacheURL: URL,
        legacyConfiguration: LegacyClaudeBrandConfiguration?,
        errorLog: ErrorLog = .shared
    ) {
        self.settingsURL = settingsURL
        self.helperDestURL = helperDestURL
        self.cacheURL = cacheURL
        self.legacyConfiguration = legacyConfiguration
        self.errorLog = errorLog
    }

    public func isHelperInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: helperDestURL.path),
              let settings = try? readSettings(),
              case let .object(statusLine) = settings.statusLine,
              statusLine.type == "command",
              let command = statusLine.command
        else { return false }
        if command == helperCommand {
            return true
        }
        guard let original = originalStatusLine(from: command) else { return false }
        return (try? wrappedStatusLine(original).command) == command
    }

    func canRemoveHelper() -> Bool {
        var artifacts = [helperDestURL, cacheURL]
        if let legacyConfiguration {
            artifacts.append(contentsOf: [legacyConfiguration.helperURL, legacyConfiguration.cacheURL])
        }
        if artifacts.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return true
        }
        guard let settings = try? readSettings() else { return false }
        return restoredStatusLine(settings.statusLine) != settings.statusLine
    }

    public func install(helperExecutableURL: URL) throws {
        let settingsBackup = try existingData(at: settingsURL)
        let helperBackup = try existingData(at: helperDestURL)
        let helperPermissions = try helperBackup.map { _ in
            try FileManager.default.attributesOfItem(atPath: helperDestURL.path)[.posixPermissions] as? NSNumber
        }
        do {
            try copyHelper(executableURL: helperExecutableURL)
            try updateSettingsForInstall()
            try verifyInstalledConfiguration()
            try migrateLegacyCacheIfNeeded()
            removeLegacyArtifacts()
        } catch {
            restoreFile(at: helperDestURL, from: helperBackup, permissions: helperPermissions ?? nil)
            restoreFile(at: settingsURL, from: settingsBackup)
            throw error
        }
    }

    func migrateLegacyInstallationIfNeeded(helperExecutableURL: URL) throws -> Bool {
        guard try hasLegacyHelperIntegration() else {
            try migrateLegacyCacheIfNeeded()
            return false
        }
        try install(helperExecutableURL: helperExecutableURL)
        return true
    }

    public func uninstall() throws {
        try removeIfPresent(cacheURL)
        if let legacyConfiguration {
            try removeIfPresent(legacyConfiguration.cacheURL)
        }
        try removeFromSettings()
        try removeIfPresent(helperDestURL)
        if let legacyConfiguration {
            try removeIfPresent(legacyConfiguration.helperURL)
        }
    }

    func installSettingsOnly() throws {
        try updateSettingsForInstall()
    }

    func uninstallSettingsOnly() throws {
        try removeFromSettings()
    }

    private func copyHelper(executableURL: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw InstallerError.helperExecutableNotFound
        }
        let destDir = helperDestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destDir,
            withIntermediateDirectories: true
        )

        let data = try Data(contentsOf: executableURL)
        try data.write(to: helperDestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperDestURL.path)
    }
}

extension StatuslineHelperInstaller {
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

    private func existingData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func restoreFile(at url: URL, from backup: Data?, permissions: NSNumber? = nil) {
        do {
            if let backup {
                try backup.write(to: url, options: .atomic)
                if let permissions {
                    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
                }
            } else {
                try removeIfPresent(url)
            }
        } catch {
            errorLog.record(
                component: "claude-code-installer", operation: "rollback",
                code: "rollback-failed", providerID: "claude-code", error: error
            )
        }
    }

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
        let original = restoredStatusLine(settings.statusLine)
        settings.statusLine = try .object(wrappedStatusLine(ClaudeSettings(statusLine: original)))
        try writeSettings(settings)
    }

    private func wrappedStatusLine(_ original: ClaudeSettings) throws -> StatusLineObject {
        var object = existingStatusLineObject(original.statusLine) ?? StatusLineObject()
        if original.statusLine == nil {
            object.command = helperCommand
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let metadata = try encoder.encode(original).base64EncodedString()
            let command = commandFromStatusLine(original.statusLine) ?? ""
            object.command = ": '\(Self.originalMarker)\(metadata)###'; "
                + wrapCommand(command)
        }
        object.type = "command"
        return object
    }

    private func existingStatusLineObject(_ value: StatusLineValue?) -> StatusLineObject? {
        if case let .object(object) = value {
            return object
        }
        return nil
    }

    private func removeFromSettings() throws {
        guard var mutable = try readSettings() else { return }
        mutable.statusLine = restoredStatusLine(mutable.statusLine)
        try writeSettings(mutable)
    }

    private func originalStatusLine(from command: String) -> ClaudeSettings? {
        let prefix = ": '\(Self.originalMarker)"
        guard command.hasPrefix(prefix) else { return nil }
        let start = command.index(command.startIndex, offsetBy: prefix.count)
        guard let end = command.range(of: "###'; ", range: start ..< command.endIndex),
              let data = Data(base64Encoded: String(command[start ..< end.lowerBound]))
        else { return nil }
        return try? JSONDecoder().decode(ClaudeSettings.self, from: data)
    }

    private func restoredStatusLine(_ value: StatusLineValue?) -> StatusLineValue? {
        guard let command = commandFromStatusLine(value) else { return value }
        if let original = originalStatusLine(from: command) {
            if var object = existingStatusLineObject(original.statusLine) {
                if let current = existingStatusLineObject(value) {
                    object.extra.merge(current.extra) { _, current in current }
                }
                return .object(object)
            }
            return original.statusLine
        }
        let helperCommands = [helperCommand, helperDestURL.path, shellQuote(helperDestURL.path)]
        let isLegacyHelper = command == legacyConfiguration?.helperURL.path
        if helperCommands.contains(command) || isLegacyHelper {
            var object = existingStatusLineObject(value) ?? StatusLineObject()
            object.command = nil
            object.type = nil
            return object.extra.isEmpty ? nil : .object(object)
        }
        let original = extractOriginalCommand(from: command)
            ?? legacyConfiguration.flatMap {
                extractOriginalCommand(from: command, chainStart: $0.chainStart, chainSeparator: $0.chainSeparator)
            }
        guard let original else { return value }
        var object = existingStatusLineObject(value) ?? StatusLineObject()
        object.command = original
        return .object(object)
    }

    private func wrapCommand(_ original: String) -> String {
        "( : '\(Self.chainStart)'; "
            + "FILBERT_INPUT=$(umask 077; mktemp \"${TMPDIR:-/tmp}/filbert-statusline.XXXXXXXXXX\") || exit 1; "
            + "trap 'rm -f -- \"$FILBERT_INPUT\"' EXIT; "
            + "trap 'exit 1' HUP INT TERM; "
            + "cat > \"$FILBERT_INPUT\" || exit 1; "
            + "( eval \(shellQuote(original)) ) < \"$FILBERT_INPUT\" & FILBERT_PREVIOUS_PID=$!; "
            + "wait \"$FILBERT_PREVIOUS_PID\" || :; "
            + ": '\(Self.chainSep)'; "
            + "\(helperCommand) < \"$FILBERT_INPUT\" > /dev/null )"
    }

    private var helperCommand: String {
        shellQuote(helperDestURL.path)
            + " --cache-path \(shellQuote(cacheURL.path))"
            + " --log-directory \(shellQuote(errorLog.fileURL.deletingLastPathComponent().path))"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

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
        guard let command = try commandFromStatusLine(readSettings()?.statusLine) else {
            return false
        }
        return command == legacyConfiguration.helperURL.path
            || command.contains(legacyConfiguration.chainStart)
    }

    private func verifyInstalledConfiguration() throws {
        guard isHelperInstalled() else {
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
        let legacyStore = StatuslineCacheStore(cacheURL: legacyConfiguration.cacheURL, errorLog: errorLog)
        guard let cache = legacyStore.read() else {
            return
        }
        let currentStore = StatuslineCacheStore(cacheURL: cacheURL, errorLog: errorLog)
        try currentStore.write(cache)
        guard currentStore.read() != nil else {
            throw InstallerError.configurationVerificationFailed
        }
        removeLegacyArtifact(legacyConfiguration.cacheURL)
    }

    private func removeLegacyArtifacts() {
        guard let legacyConfiguration else {
            return
        }
        removeLegacyArtifact(legacyConfiguration.helperURL)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            removeLegacyArtifact(legacyConfiguration.cacheURL)
        }
    }

    private func removeLegacyArtifact(_ url: URL) {
        do {
            try removeIfPresent(url)
        } catch {
            errorLog.record(
                component: "claude-code-installer", operation: "remove-legacy-artifact",
                code: "legacy-removal-failed", providerID: "claude-code", error: error
            )
        }
    }
}
