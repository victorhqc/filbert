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
    public static let providerDescription = String(
        localized: "Monitor Claude Pro/Max subscription usage"
    )
    /// Placeholder — this provider never makes network calls (providers 02 AC2).
    public static let baseURL = URL(string: "https://api.anthropic.com")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree

    /// Cache freshness threshold before `isStale` flips to `true`
    /// (providers 02 AC10).
    static let freshnessThreshold: TimeInterval = 3600

    // MARK: - Dependencies

    private let locator: ClaudeCodeLocator
    private let cacheStore: StatuslineCacheStore
    private let installer: StatuslineHelperInstaller

    public init(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(),
        cacheStore: StatuslineCacheStore = StatuslineCacheStore(),
        installer: StatuslineHelperInstaller = StatuslineHelperInstaller()
    ) {
        self.locator = locator
        self.cacheStore = cacheStore
        self.installer = installer
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
        ClaudeCodeLog.log("fetchQuota: mapped headline=\(quota.headline) lines=\(quota.lines.count) isStale=\(quota.isStale)")
        return quota
    }

    // MARK: - Mapping (providers 02 AC5, AC5b, AC6)

    private func map(cache: StatuslineCache) -> ProviderQuota {
        var lines: [UsageLine] = []

        // Map five-hour window when present (providers 02 AC5).
        if let fiveHour = cache.rateLimits?.fiveHour {
            lines.append(
                UsageLine(
                    label: String(localized: "5-hour window"),
                    percentage: fiveHour.usedPercentage,
                    resetDate: Date(timeIntervalSince1970: fiveHour.resetsAt)
                )
            )
        }

        // Map seven-day window when present (providers 02 AC5).
        if let sevenDay = cache.rateLimits?.sevenDay {
            lines.append(
                UsageLine(
                    label: String(localized: "Weekly"),
                    percentage: sevenDay.usedPercentage,
                    resetDate: Date(timeIntervalSince1970: sevenDay.resetsAt)
                )
            )
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

    /// Builds the headline using 5-hour → weekly priority
    /// (providers 02 AC6), reusing the shared `QuotaFormatting.countdown(to:)`
    /// helper so the countdown phrase is identical across providers
    /// (providers 01 AC5).
    private func computeHeadline(
        fiveHour: Window?,
        sevenDay: Window?
    ) -> String {
        let primary = fiveHour ?? sevenDay

        if let primary, primary.usedPercentage.isFinite {
            let pctString = String(format: "%.0f%%", primary.usedPercentage)
            let resetDate = Date(timeIntervalSince1970: primary.resetsAt)
            return "\(pctString) · \(QuotaFormatting.countdown(to: resetDate))"
        }

        return String(localized: "No data")
    }
}
