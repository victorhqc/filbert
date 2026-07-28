import Core
import Foundation

// MARK: - Diagnostic logging

enum ClaudeCodeLog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(
            Data("[ClaudeCodeProvider] \(message())\n".utf8)
        )
    }
}

// MARK: - Error

public enum ClaudeCodeError: Error, Equatable, Sendable {
    case binaryNotFound
    case internalInconsistency

    public static func == (lhs: ClaudeCodeError, rhs: ClaudeCodeError) -> Bool {
        switch (lhs, rhs) {
        case (.binaryNotFound, .binaryNotFound): true
        case (.internalInconsistency, .internalInconsistency): true
        default: false
        }
    }
}

extension ClaudeCodeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            String(localized: "Claude Code not found.")
        case .internalInconsistency:
            String(localized: "Internal error: unexpected auth shape.")
        }
    }
}

// MARK: - Provider

public struct ClaudeCodeProvider: AIProvider {
    // MARK: - AIProvider metadata

    public static let providerId = "claude-code"
    public static let providerName = "Claude Code"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(
        localized: "Monitor Claude Pro/Max subscription usage"
    )
    public static let automaticRefreshDisclosure: ProviderAutomaticRefreshDisclosure? =
        ProviderAutomaticRefreshDisclosure(
            command: "claude -p \"/usage\"",
            quotaName: "Claude Code"
        )
    /// Placeholder — this provider never makes network calls.
    public static let baseURL = URL(string: "https://api.anthropic.com")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static let setupHelp: ProviderSetupHelp? = ProviderSetupHelp(
        linkLabel: String(localized: "Install Claude Code"),
        url: URL(string: "https://docs.claude.com/en/docs/claude-code/overview")!
    )

    static let freshnessThreshold: TimeInterval = 3600

    // MARK: - Dependencies

    private let locator: ClaudeCodeLocator
    private let cacheStore: StatuslineCacheStore
    private let installer: StatuslineHelperInstaller
    private let refresher: ClaudeCodeRefresher

    public init(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(),
        cacheStore: StatuslineCacheStore = StatuslineCacheStore(),
        installer: StatuslineHelperInstaller = StatuslineHelperInstaller(),
        refresher: ClaudeCodeRefresher = ClaudeCodeRefresher()
    ) {
        self.locator = locator
        self.cacheStore = cacheStore
        self.installer = installer
        self.refresher = refresher
    }

    // MARK: - Configuration

    public func isConfigured() -> Bool {
        let binaryPath = locator.resolve()
        let helperInstalled = installer.isHelperInstalled()
            || installer.hasLegacyHelperInstallation()
        ClaudeCodeLog.log("isConfigured: binary=\(binaryPath ?? "nil") helperInstalled=\(helperInstalled)")
        return binaryPath != nil && helperInstalled
    }

    public func currentSetupState() async -> ProviderState? {
        if locator.resolve() == nil {
            return .setup(String(localized: "Claude Code not found"))
        }
        if !installer.isHelperInstalled() {
            guard let sourceURL = helperSourceURL else {
                return .setup(String(localized: "Helper source file not found in app bundle."))
            }
            do {
                _ = try await Task.detached {
                    try installer.migrateLegacyInstallationIfNeeded(
                        helperSourceURL: sourceURL
                    )
                }.value
            } catch {
                ClaudeCodeLog.log(
                    "legacy helper migration failed: \(error.localizedDescription)"
                )
                return .setup(
                    String(
                        localized: "Automatic helper migration failed. Select Install Helper to retry."
                    )
                )
            }
            if !installer.isHelperInstalled() {
                return .setup(String(localized: "Helper not installed"))
            }
        }
        return nil
    }

    // MARK: - Helper management

    public func canInstallHelper() -> Bool {
        locator.resolve() != nil && !installer.isHelperInstalled()
    }

    public func installHelper() async throws {
        guard let sourceURL = helperSourceURL else {
            ClaudeCodeLog.log("installHelper: helper source not found in bundle")
            throw InstallerError.helperSourceNotFound
        }
        let binaryPath = locator.resolve()
        ClaudeCodeLog.log("installHelper: binary=\(binaryPath ?? "nil") source=\(sourceURL.path)")
        try await Task.detached {
            try installer.install(helperSourceURL: sourceURL)
        }.value
        ClaudeCodeLog.log("installHelper: install ok, helperInstalled=\(installer.isHelperInstalled())")
    }

    public func removeHelper() async throws {
        try installer.uninstall()
    }

    private var helperSourceURL: URL? {
        Bundle.module.url(
            forResource: "statusline_helper",
            withExtension: "swift"
        )
    }

    // MARK: - Quota fetch

    public func fetchQuota(
        auth: ProviderAuth,
        baseURL _: URL
    ) async throws -> ProviderQuota {
        guard case .apiKeyFree = auth else {
            ClaudeCodeLog.log("fetchQuota: rejected non-apiKeyFree auth")
            throw ClaudeCodeError.internalInconsistency
        }

        ClaudeCodeLog.log("fetchQuota: start configured=\(isConfigured())")

        guard let cache = cacheStore.read() else {
            ClaudeCodeLog.log("fetchQuota: no cache — returning No data")
            return ProviderQuota(
                providerId: Self.providerId,
                providerName: Self.providerName,
                headline: String(localized: "No data"),
                lines: [],
                lastUpdated: Date(),
                error: String(
                    localized: "Open Claude Code to populate usage data"
                )
            )
        }

        let quota = map(cache: cache)
        ClaudeCodeLog.log(
            "fetchQuota: mapped headline=\(quota.headline) lines=\(quota.lines.count) isStale=\(quota.isStale)"
        )
        return quota
    }

    // MARK: - Mapping

    private func map(cache: StatuslineCache) -> ProviderQuota {
        var lines: [UsageLine] = []

        if let fiveHour = cache.rateLimits?.fiveHour {
            lines.append(usageLine(label: String(localized: "5-hour window"), window: fiveHour))
        }

        if let sevenDay = cache.rateLimits?.sevenDay {
            lines.append(usageLine(label: String(localized: "Weekly"), window: sevenDay))
        }

        let headline = computeHeadline(
            fiveHour: cache.rateLimits?.fiveHour,
            sevenDay: cache.rateLimits?.sevenDay
        )

        let lastUpdated = Date(timeIntervalSince1970: cache.writtenAt)

        let age = Date().timeIntervalSince(lastUpdated)
        let isStale = age > Self.freshnessThreshold

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: lastUpdated,
            isStale: isStale
        )
    }

    private func usageLine(label: String, window: Window) -> UsageLine {
        UsageLine(
            label: label,
            percentage: window.usedPercentage,
            resetDate: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func computeHeadline(
        fiveHour: Window?,
        sevenDay: Window?
    ) -> String {
        guard let primary = fiveHour ?? sevenDay else {
            return String(localized: "No data")
        }

        let countdown = primary.resetsAt.map {
            QuotaFormatting.countdown(to: Date(timeIntervalSince1970: $0))
        }

        if let usedPercentage = primary.usedPercentage, usedPercentage.isFinite {
            let pctString = String(format: "%.0f%%", usedPercentage)
            if let countdown {
                return "\(pctString) · \(countdown)"
            }
            return pctString
        }

        return countdown ?? String(localized: "No data")
    }
}

// MARK: - ProactiveRefreshable

extension ClaudeCodeProvider: ProactiveRefreshable {
    public func proactiveRefresh() async throws {
        ClaudeCodeLog.log("proactiveRefresh: delegating to refresher")
        try await refresher.refresh()
    }
}
