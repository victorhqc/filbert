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
    public static let refreshCharacteristics = ProviderRefreshCharacteristics(
        costEvidence: .unknown,
        canInvokeInference: false
    )

    static let primaryWindowLineId = "primary-window-usage"
    static let secondaryWindowLineId = "secondary-window-usage"
    static let subscriptionLimitGroup = "subscription"

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

        let read = try await coordinator.readRateLimits(
            using: client,
            executablePath: executablePath
        )
        return map(read.result, receivedAt: read.receivedAt)
    }

    func map(_ result: CodexRateLimitReadResult, receivedAt: Date) -> ProviderQuota {
        let snapshot = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        let windows = windowEntries(in: snapshot)
        let credits = creditsBalance(for: snapshot?.credits)
        var lines = windows.map(usageLine(for:))
        if let credits {
            lines.append(creditsLine(for: credits))
        }
        let headlineWindow = shortestWindow(in: windows)

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline(for: headlineWindow?.window),
            lines: lines,
            lastUpdated: receivedAt,
            activityObservation: activityObservation(for: windows, credits: credits, receivedAt: receivedAt),
            headlineUsageLineId: headlineWindow?.id
        )
    }

    private struct WindowEntry {
        let id: String
        let window: CodexRateLimitWindow
    }

    private func windowEntries(in snapshot: CodexRateLimitSnapshot?) -> [WindowEntry] {
        [
            (Self.primaryWindowLineId, snapshot?.primary),
            (Self.secondaryWindowLineId, snapshot?.secondary),
        ].compactMap { id, window in
            window.map { WindowEntry(id: id, window: $0) }
        }
    }

    private func shortestWindow(in windows: [WindowEntry]) -> WindowEntry? {
        windows.min {
            ($0.window.windowDurationMins ?? .max) < ($1.window.windowDurationMins ?? .max)
        }
    }

    private func activityObservation(
        for windows: [WindowEntry],
        credits: CodexCreditsBalance?,
        receivedAt: Date
    ) -> ProviderActivityObservation {
        var metrics = windows.compactMap { entry in
            entry.window.usedPercent.map { percentage in
                ProviderActivityMetric(
                    id: entry.id,
                    kind: .usage,
                    value: .number(Decimal(percentage))
                )
            }
        }
        if let creditsMetric = credits.flatMap({ creditsMetric(for: $0, receivedAt: receivedAt) }) {
            metrics.append(creditsMetric)
        }

        // Each `account/rateLimits/read` asks the backend; nothing is cached.
        return ProviderActivityObservation(metrics: metrics, freshness: .fresh)
    }

    private func usageLine(for entry: WindowEntry) -> UsageLine {
        UsageLine(
            label: windowLabel(for: entry.window.windowDurationMins),
            percentage: entry.window.usedPercent,
            resetDate: entry.window.resetsAt.map { Date(timeIntervalSince1970: $0) },
            windowDuration: entry.window.windowDurationMins.map { TimeInterval($0) * 60 },
            id: entry.id,
            limitGroup: Self.subscriptionLimitGroup
        )
    }

    private func headline(for shortestWindow: CodexRateLimitWindow?) -> String {
        guard let shortestWindow else {
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

private struct CodexRateLimitRead: Sendable {
    let result: CodexRateLimitReadResult
    let receivedAt: Date
}

private actor CodexFetchCoordinator {
    private var inFlight: Task<CodexRateLimitRead, Error>?

    func readRateLimits(
        using client: CodexAppServerClient,
        executablePath: String
    ) async throws -> CodexRateLimitRead {
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task {
            let result = try await client.readRateLimits(at: executablePath)
            return CodexRateLimitRead(result: result, receivedAt: Date())
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
