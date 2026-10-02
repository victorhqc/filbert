import Core
import Foundation

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

extension ClaudeCodeError: DiagnosticError {
    public var diagnosticCode: String {
        switch self {
        case .binaryNotFound: "binary-not-found"
        case .internalInconsistency: "invalid-auth-shape"
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
    private let errorLog: ErrorLog

    public init(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(),
        cacheStore: StatuslineCacheStore = StatuslineCacheStore(),
        installer: StatuslineHelperInstaller = StatuslineHelperInstaller(),
        refresher: ClaudeCodeRefresher = ClaudeCodeRefresher(),
        errorLog: ErrorLog = .shared
    ) {
        self.locator = locator
        self.cacheStore = cacheStore
        self.installer = installer
        self.refresher = refresher
        self.errorLog = errorLog
    }

    // MARK: - Configuration

    public func isConfigured() -> Bool {
        let binaryPath = locator.resolve()
        let helperInstalled = installer.isHelperInstalled()
        return binaryPath != nil && helperInstalled
    }

    public func currentSetupState() async -> ProviderState? {
        if locator.resolve() == nil {
            return .setup(String(localized: "Claude Code not found"))
        }
        if !installer.isHelperInstalled() {
            guard let executableURL = StatuslineHelperResource.resolve() else {
                errorLog.record(
                    component: "claude-code-provider", operation: "resolve-helper",
                    code: "helper-executable-missing", providerID: Self.providerId
                )
                return .error(InstallerError.helperExecutableNotFound.localizedDescription)
            }
            do {
                _ = try await Task.detached {
                    try installer.migrateLegacyInstallationIfNeeded(
                        helperExecutableURL: executableURL
                    )
                }.value
            } catch {
                errorLog.record(
                    component: "claude-code-provider", operation: "migrate-helper",
                    code: "helper-migration-failed", providerID: Self.providerId, error: error
                )
                return .error(
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

    public func canRemoveHelper() -> Bool {
        installer.canRemoveHelper()
    }

    public func installHelper() async throws {
        guard let executableURL = StatuslineHelperResource.resolve() else {
            throw InstallerError.helperExecutableNotFound
        }
        try await Task.detached {
            try installer.install(helperExecutableURL: executableURL)
        }.value
    }

    public func removeHelper() async throws {
        try installer.uninstall()
    }

    // MARK: - Quota fetch

    public func fetchQuota(
        auth: ProviderAuth,
        baseURL _: URL
    ) async throws -> ProviderQuota {
        guard case .apiKeyFree = auth else {
            throw ClaudeCodeError.internalInconsistency
        }

        guard let cache = try cacheStore.readForQuota() else {
            return ProviderQuota(
                providerId: Self.providerId,
                providerName: Self.providerName,
                headline: String(localized: "No data"),
                lines: [],
                lastUpdated: .distantPast,
                error: String(
                    localized: "Open Claude Code to populate usage data"
                )
            )
        }

        return map(cache: cache)
    }

    // MARK: - Mapping

    private func map(cache: StatuslineCache) -> ProviderQuota {
        var lines: [UsageLine] = []
        let fiveHour = cache.rateLimits?.fiveHour?.populated
        let sevenDay = cache.rateLimits?.sevenDay?.populated

        if let fiveHour {
            lines.append(usageLine(
                label: String(localized: "5-hour window"),
                window: fiveHour,
                windowDuration: UsageWindowDuration.fiveHours
            ))
        }

        if let sevenDay {
            lines.append(usageLine(
                label: String(localized: "Weekly"),
                window: sevenDay,
                windowDuration: UsageWindowDuration.week
            ))
        }

        let headline = computeHeadline(
            fiveHour: fiveHour,
            sevenDay: sevenDay
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
            error: lines.isEmpty ? String(localized: "Open Claude Code to populate usage data") : nil,
            isStale: isStale,
            activityObservation: activityObservation(from: cache.rateLimits)
        )
    }

    private func activityObservation(from rateLimits: RateLimits?) -> ProviderActivityObservation {
        let metrics = [
            activityMetric(id: "five-hour-usage", window: rateLimits?.fiveHour),
            activityMetric(id: "weekly-usage", window: rateLimits?.sevenDay),
        ].compactMap { $0 }
        return ProviderActivityObservation(metrics: metrics)
    }

    private func activityMetric(id: String, window: Window?) -> ProviderActivityMetric? {
        guard let percentage = window?.usedPercentage else { return nil }
        return ProviderActivityMetric(
            id: id,
            kind: .usage,
            value: .number(Decimal(percentage))
        )
    }

    private func usageLine(
        label: String,
        window: Window,
        windowDuration: TimeInterval
    ) -> UsageLine {
        UsageLine(
            label: label,
            percentage: window.usedPercentage,
            resetDate: window.resetsAt.map { Date(timeIntervalSince1970: $0) },
            windowDuration: windowDuration
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
        try await refresher.refresh()
    }
}
