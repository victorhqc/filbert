import Core
import Foundation

public enum OpenAICodexError: Error, Equatable, Sendable {
    case binaryNotFound
    case internalInconsistency
}

extension OpenAICodexError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            String(localized: "Codex CLI not installed")
        case .internalInconsistency:
            String(localized: "Internal error: unexpected auth shape.")
        }
    }
}

public struct OpenAICodexProvider: AIProvider {
    public static let providerId = "openai-codex"
    public static let providerName = "OpenAI Codex"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(
        localized: "Monitor Codex subscription usage"
    )
    /// Placeholder required by `AIProvider`; the provider has no HTTP endpoint.
    public static let baseURL = URL(string: "https://chatgpt.com")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static let setupHelp: ProviderSetupHelp? = ProviderSetupHelp(
        linkLabel: String(localized: "Install Codex CLI"),
        url: URL(string: "https://developers.openai.com/codex/cli/")!
    )

    private let locator: CodexLocator
    private let client: CodexAppServerClient
    private let coordinator: CodexFetchCoordinator

    public init() {
        self.init(locator: CodexLocator(), client: CodexAppServerClient())
    }

    init(locator: CodexLocator, client: CodexAppServerClient) {
        self.locator = locator
        self.client = client
        coordinator = CodexFetchCoordinator()
    }

    public func isConfigured() -> Bool {
        locator.resolve() != nil
    }

    public func currentSetupState() async -> ProviderState? {
        guard !isConfigured() else { return nil }
        return .setup(String(localized: "Codex CLI not installed"))
    }

    public func fetchQuota(
        auth: ProviderAuth,
        baseURL _: URL
    ) async throws -> ProviderQuota {
        guard case .apiKeyFree = auth else {
            throw OpenAICodexError.internalInconsistency
        }
        guard let executablePath = locator.resolve() else {
            throw OpenAICodexError.binaryNotFound
        }

        let result = try await coordinator.readRateLimits(
            using: client,
            executablePath: executablePath
        )
        return map(result)
    }

    func map(_ result: CodexRateLimitReadResult) -> ProviderQuota {
        let snapshot = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        let windows = [snapshot?.primary, snapshot?.secondary].compactMap { $0 }
        var lines = windows.map(usageLine)

        if let details = creditDetails(for: snapshot?.credits) {
            if let firstLine = lines.first {
                lines[0] = UsageLine(
                    label: firstLine.label,
                    percentage: firstLine.percentage,
                    resetDate: firstLine.resetDate,
                    windowDuration: firstLine.windowDuration,
                    details: details
                )
            } else {
                lines.append(UsageLine(label: String(localized: "Credits"), details: details))
            }
        }

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline(for: windows),
            lines: lines,
            lastUpdated: Date(),
            activityObservation: activityObservation(for: snapshot)
        )
    }

    private func activityObservation(
        for snapshot: CodexRateLimitSnapshot?
    ) -> ProviderActivityObservation {
        var metrics: [ProviderActivityMetric] = []

        if let primary = snapshot?.primary?.usedPercent {
            metrics.append(ProviderActivityMetric(
                id: "primary-window-usage",
                kind: .usage,
                value: .number(Decimal(primary))
            ))
        }
        if let secondary = snapshot?.secondary?.usedPercent {
            metrics.append(ProviderActivityMetric(
                id: "secondary-window-usage",
                kind: .usage,
                value: .number(Decimal(secondary))
            ))
        }
        if snapshot?.credits?.unlimited == true {
            metrics.append(ProviderActivityMetric(
                id: "credits",
                kind: .credits,
                value: .discrete("unlimited")
            ))
        } else if let balance = snapshot?.credits?.balance {
            appendNumericCreditMetric(balance, to: &metrics)
        }

        return ProviderActivityObservation(metrics: metrics)
    }

    private func appendNumericCreditMetric(
        _ balance: String,
        to metrics: inout [ProviderActivityMetric]
    ) {
        guard let value = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")) else {
            return
        }
        metrics.append(ProviderActivityMetric(
            id: "credits",
            kind: .credits,
            value: .number(value)
        ))
    }

    private func usageLine(_ window: CodexRateLimitWindow) -> UsageLine {
        UsageLine(
            label: windowLabel(for: window.windowDurationMins),
            percentage: window.usedPercent,
            resetDate: window.resetsAt.map { Date(timeIntervalSince1970: $0) },
            windowDuration: window.windowDurationMins.map { TimeInterval($0) * 60 }
        )
    }

    private func creditDetails(for credits: CodexCredits?) -> [UsageDetail]? {
        guard let credits else { return nil }
        if credits.unlimited == true {
            return [UsageDetail(label: String(localized: "Credits"), value: String(localized: "Unlimited credits"))]
        }
        guard let balance = credits.balance else { return nil }
        return [
            UsageDetail(
                label: String(localized: "Credits"),
                value: balance
            ),
        ]
    }

    private func headline(for windows: [CodexRateLimitWindow]) -> String {
        guard let shortestWindow = windows.min(by: {
            ($0.windowDurationMins ?? .max) < ($1.windowDurationMins ?? .max)
        }) else {
            return String(localized: "No usage limits reported")
        }

        let percentage = shortestWindow.usedPercent.map { String(format: "%.0f%%", $0) }
        let countdown = shortestWindow.resetsAt.map {
            QuotaFormatting.countdown(to: Date(timeIntervalSince1970: $0))
        }

        return switch (percentage, countdown) {
        case let (.some(percentage), .some(countdown)): "\(percentage) · \(countdown)"
        case let (.some(percentage), .none): percentage
        case let (.none, .some(countdown)): countdown
        case (.none, .none): String(localized: "No usage limits reported")
        }
    }

    private func windowLabel(for duration: Int?) -> String {
        switch duration {
        case 300:
            String(localized: "5-hour window")
        case 10080:
            String(localized: "Weekly")
        case let .some(minutes):
            String.localizedStringWithFormat(String(localized: "%lld-minute window"), Int64(minutes))
        case .none:
            String(localized: "Usage window")
        }
    }
}

private actor CodexFetchCoordinator {
    private var inFlight: Task<CodexRateLimitReadResult, Error>?

    func readRateLimits(
        using client: CodexAppServerClient,
        executablePath: String
    ) async throws -> CodexRateLimitReadResult {
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task {
            try await client.readRateLimits(at: executablePath)
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
