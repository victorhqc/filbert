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
            String(displayLocalized: "Codex CLI not installed", bundle: .module)
        case .internalInconsistency:
            String(displayLocalized: "Internal error: unexpected credential type.", bundle: .module)
        }
    }
}

extension OpenAICodexError: DiagnosticError {
    public var diagnosticCode: String {
        switch self {
        case .binaryNotFound: "binary-not-found"
        case .internalInconsistency: "internal-inconsistency"
        }
    }
}

public struct OpenAICodexProvider: AIProvider {
    public static let providerId = "openai-codex"
    public static let providerName = "OpenAI Codex"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor Codex subscription usage", bundle: .module)
    }

    /// Placeholder required by `AIProvider`; the provider has no HTTP endpoint.
    public static let baseURL = URL(string: "https://chatgpt.com")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static var setupHelp: ProviderSetupHelp? {
        ProviderSetupHelp(
            linkLabel: String(displayLocalized: "Install Codex CLI", bundle: .module),
            url: URL(string: "https://developers.openai.com/codex/cli/")!
        )
    }

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
        return .setup(DisplayText { String(displayLocalized: "Codex CLI not installed", bundle: .module) })
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
                    value: .number(Decimal(percentage)),
                    forecastDescriptor: forecastDescriptor(for: entry, usedPercent: percentage, receivedAt: receivedAt)
                )
            }
        }
        if let creditsMetric = credits.flatMap({ creditsMetric(for: $0, receivedAt: receivedAt) }) {
            metrics.append(creditsMetric)
        }

        // Each `account/rateLimits/read` asks the backend; nothing is cached.
        return ProviderActivityObservation(metrics: metrics, freshness: .fresh)
    }

    /// An unused window reports 0% and moves its `resetsAt` with each read.
    private func forecastDescriptor(
        for entry: WindowEntry,
        usedPercent: Double,
        receivedAt: Date
    ) -> AllowanceForecastDescriptor? {
        guard usedPercent > 0,
              let resetsAt = entry.window.resetsAt,
              let minutes = entry.window.windowDurationMins, minutes > 0
        else {
            return nil
        }
        return AllowanceForecastDescriptor(
            accounting: .fixedPeriod(
                limit: 100,
                resetsAt: Date(timeIntervalSince1970: resetsAt),
                length: TimeInterval(minutes) * 60
            ),
            unit: .percentagePoints,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: entry.id
        )
    }

    private func usageLine(for entry: WindowEntry) -> UsageLine {
        let duration = entry.window.windowDurationMins
        return UsageLine(
            label: DisplayText { Self.windowLabel(for: duration) },
            percentage: entry.window.usedPercent,
            resetDate: entry.window.resetsAt.map { Date(timeIntervalSince1970: $0) },
            windowDuration: entry.window.windowDurationMins.map { TimeInterval($0) * 60 },
            id: entry.id,
            limitGroup: Self.subscriptionLimitGroup
        )
    }

    private func headline(for shortestWindow: CodexRateLimitWindow?) -> DisplayText {
        let usedPercent = shortestWindow?.usedPercent
        let resetsAt = shortestWindow?.resetsAt
        return DisplayText {
            let percentage = usedPercent.map(QuotaFormatting.percentage)
            let countdown = resetsAt.map {
                QuotaFormatting.countdown(to: Date(timeIntervalSince1970: $0))
            }

            return switch (percentage, countdown) {
            case let (.some(percentage), .some(countdown)): "\(percentage) · \(countdown)"
            case let (.some(percentage), .none): percentage
            case let (.none, .some(countdown)): countdown
            case (.none, .none): String(displayLocalized: "No usage limits reported", bundle: .module)
            }
        }
    }

    private static func windowLabel(for duration: Int?) -> String {
        switch duration {
        case 300:
            String(displayLocalized: "5-hour window", bundle: .module)
        case 10080:
            String(displayLocalized: "Weekly", bundle: .module)
        case let .some(minutes):
            String(displayLocalized: "\(minutes)-minute window", bundle: .module)
        case .none:
            String(displayLocalized: "Usage window", bundle: .module)
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
