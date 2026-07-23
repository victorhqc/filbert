import Core
import Foundation

// MARK: - Diagnostic logging

/// Lightweight stderr logger — diagnostic only. Mirrors the pattern in
/// ZAIProvider so both providers log consistently.
enum ClaudeCodeLog {
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(
            Data("[ClaudeCodeProvider] \(message())\n".utf8)
        )
    }
}

// MARK: - Error

public enum ClaudeCodeError: Error, Equatable, Sendable {
    /// The binary is not installed anywhere the locator checks (providers 02 AC1).
    case binaryNotFound
    /// The registry routed `.apiKey` auth — contract-integrity violation
    /// (providers 02 AC2).
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

// MARK: - Provider (providers 02)

public struct ClaudeCodeProvider: AIProvider {
    // MARK: - AIProvider metadata

    public static let providerId = "claude-code"
    public static let providerName = "Claude Code"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(
        localized: "Monitor Claude Pro/Max subscription usage"
    )
    /// Placeholder — this provider never makes network calls (providers 02 AC2).
    public static let baseURL = URL(string: "https://api.anthropic.com")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static let setupHelp: ProviderSetupHelp? = ProviderSetupHelp(
        linkLabel: String(localized: "Install Claude Code"),
        url: URL(string: "https://docs.claude.com/en/docs/claude-code/overview")!
    )

    /// Cache freshness threshold before `isStale` flips to `true`
    /// (providers 02 AC10).
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

    // MARK: - Configuration (providers 02 AC3, core 03 AC5/AC6)

    /// Returns `true` when the `claude` binary is locatable and the helper
    /// is installed (providers 02 AC1, AC7, AC8).
    public func isConfigured() -> Bool {
        let binaryPath = locator.resolve()
        let helperInstalled = installer.isHelperInstalled()
        ClaudeCodeLog.log("isConfigured: binary=\(binaryPath ?? "nil") helperInstalled=\(helperInstalled)")
        return binaryPath != nil && helperInstalled
    }

    /// Reports the current setup state so the Settings row can show why
    /// the provider is not ready (core 03 AC6).
    public func currentSetupState() async -> ProviderState? {
        if locator.resolve() == nil {
            return .setup(String(localized: "Claude Code not found"))
        }
        if !installer.isHelperInstalled() {
            return .setup(String(localized: "Helper not installed"))
        }
        return nil
    }

    // MARK: - Helper management (ui 05 AC4/AC5)

    /// Returns `true` when the `claude` binary is present but the helper is
    /// not yet installed — the Settings row uses this to decide whether to
    /// show the "Install Helper" button (ui 05 AC3/AC4).
    public func canInstallHelper() -> Bool {
        locator.resolve() != nil && !installer.isHelperInstalled()
    }

    /// Compiles the helper binary and chains it into
    /// `~/.claude/settings.json` (providers 02 AC7, ui 05 AC4).
    public func installHelper() async throws {
        guard let sourceURL = Bundle.module.url(
            forResource: "statusline_helper",
            withExtension: "swift"
        ) else {
            ClaudeCodeLog.log("installHelper: helper source not found in bundle")
            throw InstallerError.helperSourceNotFound
        }
        let binaryPath = locator.resolve()
        ClaudeCodeLog.log("installHelper: binary=\(binaryPath ?? "nil") source=\(sourceURL.path)")
        try installer.install(helperSourceURL: sourceURL)
        ClaudeCodeLog.log("installHelper: install ok, helperInstalled=\(installer.isHelperInstalled())")
    }

    /// Removes the helper binary, unwraps the chain from
    /// `~/.claude/settings.json`, and deletes the cache file
    /// (providers 02 AC11, ui 05 AC5).
    public func removeHelper() async throws {
        try installer.uninstall()
    }

    // MARK: - Quota fetch (providers 02 AC2, AC4–AC6, AC10)

    public func fetchQuota(
        auth: ProviderAuth,
        baseURL _: URL
    ) async throws -> ProviderQuota {
        // Only .apiKeyFree should reach us (providers 02 AC2).
        guard case .apiKeyFree = auth else {
            ClaudeCodeLog.log("fetchQuota: rejected non-apiKeyFree auth")
            throw ClaudeCodeError.internalInconsistency
        }

        ClaudeCodeLog.log("fetchQuota: start configured=\(isConfigured())")

        // Read the cache file — this provider never touches the network
        // (providers 02 AC4).
        guard let cache = cacheStore.read() else {
            // No cache file yet: the provider is configured but has no data.
            // Surface as a data-level error per (providers 02 AC10).
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

    // MARK: - Mapping (providers 02 AC5, AC5b, AC6)

    private func map(cache: StatuslineCache) -> ProviderQuota {
        var lines: [UsageLine] = []

        // Map five-hour window when present (providers 02 AC5).
        if let fiveHour = cache.rateLimits?.fiveHour {
            lines.append(usageLine(label: String(localized: "5-hour window"), window: fiveHour))
        }

        // Map seven-day window when present (providers 02 AC5).
        if let sevenDay = cache.rateLimits?.sevenDay {
            lines.append(usageLine(label: String(localized: "Weekly"), window: sevenDay))
        }

        let headline = computeHeadline(
            fiveHour: cache.rateLimits?.fiveHour,
            sevenDay: cache.rateLimits?.sevenDay
        )

        let lastUpdated = Date(timeIntervalSince1970: cache.writtenAt)

        // Staleness: true when written_at is older than the freshness
        // threshold (providers 02 AC5b, AC10).
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

    /// Builds one usage line for a window: a percentage (rendered as a bar
    /// when present) and a reset countdown (when the reset time is known).
    private func usageLine(label: String, window: Window) -> UsageLine {
        UsageLine(
            label: label,
            percentage: window.usedPercentage,
            resetDate: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// Builds the headline using 5-hour → weekly priority
    /// (providers 02 AC6), reusing the shared `QuotaFormatting.countdown(to:)`
    /// helper so the countdown phrase is identical across providers
    /// (providers 01 AC5): `"35% · resets in 4 hours"`. Falls back to the
    /// countdown alone if a window somehow has a reset but no percentage.
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

// MARK: - ProactiveRefreshable (providers 03 AC3)

extension ClaudeCodeProvider: ProactiveRefreshable {
    /// Triggers a window-less `claude -p` spawn via the refresher before the
    /// next `fetchQuota` call re-reads the cache (providers 03 AC3).
    ///
    /// The view model only invokes this on a manual Refresh click — the
    /// auto-refresh loop still goes straight to `fetchQuota` and never
    /// spawns `claude`.
    public func proactiveRefresh() async throws {
        ClaudeCodeLog.log("proactiveRefresh: delegating to refresher")
        try await refresher.refresh()
    }
}
