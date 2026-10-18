import Core
import Foundation
import Security

struct GeminiQuotaRequest: Encodable, Sendable {
    let project: String
}

struct GeminiQuotaResponse: Decodable, Sendable {
    let buckets: [GeminiQuotaBucket]?
}

struct GeminiQuotaBucket: Decodable, Sendable {
    let remainingAmount: String?
    let remainingFraction: Double?
    let resetTime: String?
    let tokenType: String?
    let modelId: String?
}

public struct GeminiCLIProvider: AIProvider {
    public static let providerId = "gemini-cli"
    public static let providerName = "Gemini CLI"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor Gemini CLI model quotas", bundle: .module)
    }

    public static var providerDisclaimer: String? {
        String(
            displayLocalized: """
            This provider uses Google's private Code Assist interface and may need an update if Google changes it.
            """,
            bundle: .module
        )
    }

    public static let baseURL = URL(string: "https://cloudcode-pa.googleapis.com")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static var setupHelp: ProviderSetupHelp? {
        ProviderSetupHelp(
            linkLabel: String(displayLocalized: "Install Gemini CLI", bundle: .module),
            url: URL(
                string: "https://google-gemini.github.io/gemini-cli/docs/get-started/authentication.html"
            )!
        )
    }

    let credentialStore: any GeminiCredentialStore
    private let oauth: GeminiOAuthClient
    private let codeAssist: GeminiCodeAssistClient
    private let gate: ProviderRetryGate
    private let coordinator: GeminiFetchCoordinator
    private let now: @Sendable () -> Date
    let errorLog: ErrorLog

    public var retryGate: ProviderRetryGate? {
        gate
    }

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(
            configuration: configuration,
            delegate: GeminiRedirectDelegate(),
            delegateQueue: nil
        )
        let transport = URLSessionGeminiHTTPTransport(session: session)
        let gate = ProviderRetryGate()
        let http = GeminiHTTPClient(transport: transport, retryGate: gate)
        self.init(
            credentialStore: GeminiKeychainStore(),
            oauth: GeminiOAuthClient(http: http),
            codeAssist: GeminiCodeAssistClient(http: http),
            retryGate: gate
        )
    }

    init(
        credentialStore: any GeminiCredentialStore,
        oauth: GeminiOAuthClient,
        codeAssist: GeminiCodeAssistClient,
        retryGate: ProviderRetryGate,
        now: (@Sendable () -> Date)? = nil,
        workflowTimeout: TimeInterval = 90,
        errorLog: ErrorLog = .shared
    ) {
        self.credentialStore = credentialStore
        self.oauth = oauth
        self.codeAssist = codeAssist
        gate = retryGate
        coordinator = GeminiFetchCoordinator(timeout: workflowTimeout)
        self.now = now ?? { Date() }
        self.errorLog = errorLog
    }

    public func fetchQuota(
        auth: ProviderAuth,
        baseURL _: URL
    ) async throws -> ProviderQuota {
        guard case .apiKeyFree = auth else {
            throw GeminiCLIError.internalInconsistency
        }
        return try await coordinator.fetch {
            try await performFetch()
        }
    }

    func map(_ response: GeminiQuotaResponse) throws -> ProviderQuota {
        guard let responseBuckets = response.buckets, !responseBuckets.isEmpty else {
            return ProviderQuota(
                providerId: Self.providerId,
                providerName: Self.providerName,
                headline: DisplayText { String(displayLocalized: "No usage limits reported", bundle: .module) },
                lines: [],
                lastUpdated: Date(),
                activityObservation: ProviderActivityObservation(metrics: [])
            )
        }
        let mapped = responseBuckets.compactMap { bucket -> GeminiMappedBucket? in
            guard let modelId = bucket.modelId, !modelId.isEmpty,
                  let remaining = bucket.remainingFraction,
                  remaining.isFinite, (0 ... 1).contains(remaining)
            else {
                return nil
            }
            let resetDate = parseDate(bucket.resetTime)
            guard bucket.resetTime == nil || resetDate != nil else {
                return nil
            }
            return GeminiMappedBucket(
                modelId: modelId,
                tokenType: bucket.tokenType,
                remainingFraction: remaining,
                resetDate: resetDate,
                remainingAmount: bucket.remainingAmount
            )
        }
        guard !mapped.isEmpty else {
            throw GeminiCLIError.payloadDrift
        }
        let buckets = mapped.sorted(by: GeminiMappedBucket.order)
        guard let headlineBucket = mapped.min(by: GeminiMappedBucket.constrainedOrder) else {
            throw GeminiCLIError.internalInconsistency
        }
        let lines = buckets.map(usageLine)
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline(for: headlineBucket),
            lines: lines,
            lastUpdated: Date(),
            activityObservation: ProviderActivityObservation(
                metrics: buckets.map(activityMetric)
            )
        )
    }

    private func performFetch() async throws -> ProviderQuota {
        let credentials: GeminiCredentials
        do {
            guard let loaded = try credentialStore.load() else {
                throw ProviderSetupError.missingCredentials
            }
            credentials = loaded
        } catch let error as GeminiCredentialError {
            switch error {
            case .itemNotFound:
                throw ProviderSetupError.missingCredentials
            case .accessDenied(errSecUserCanceled):
                throw CancellationError()
            case .accessDenied:
                throw GeminiCLIError.keychainAccessDenied
            case .invalidPayload:
                throw GeminiCLIError.invalidCredentials
            }
        }

        let accessToken: String
        let tokenIsValid = credentials.expiresAt.map {
            $0 > now().addingTimeInterval(60)
        } ?? true
        if let storedAccessToken = credentials.accessToken, !storedAccessToken.isEmpty, tokenIsValid {
            accessToken = storedAccessToken
        } else {
            guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
                throw GeminiCLIError.signedOut
            }
            accessToken = try await oauth.exchange(refreshToken: refreshToken)
        }
        let project = try await codeAssist.resolveProject(accessToken: accessToken)
        let response = try await codeAssist.retrieveQuota(
            accessToken: accessToken,
            project: project
        )
        return try map(response)
    }

    private func usageLine(_ bucket: GeminiMappedBucket) -> UsageLine {
        let label = DisplayText {
            String.localizedStringWithFormat(
                String(displayLocalized: "%@ · %@", bundle: .module),
                bucket.modelId,
                Self.tokenTypeLabel(bucket.tokenType)
            )
        }
        let details = bucket.remainingAmount.map {
            [UsageDetail(
                label: DisplayText { String(displayLocalized: "Remaining", bundle: .module) },
                value: DisplayText(verbatim: $0)
            )]
        }
        return UsageLine(
            label: label,
            percentage: (1 - bucket.remainingFraction) * 100,
            resetDate: bucket.resetDate,
            details: details
        )
    }

    private func headline(for bucket: GeminiMappedBucket) -> DisplayText {
        let usedPercentage = (1 - bucket.remainingFraction) * 100
        guard let resetDate = bucket.resetDate else {
            return DisplayText {
                String.localizedStringWithFormat(
                    String(displayLocalized: "%@ used", bundle: .module),
                    QuotaFormatting.percentage(usedPercentage)
                )
            }
        }
        return DisplayText {
            String.localizedStringWithFormat(
                String(displayLocalized: "%@ used · %@", bundle: .module),
                QuotaFormatting.percentage(usedPercentage),
                QuotaFormatting.countdown(to: resetDate)
            )
        }
    }

    private func activityMetric(_ bucket: GeminiMappedBucket) -> ProviderActivityMetric {
        let tokenType = bucket.tokenType ?? "unknown"
        return ProviderActivityMetric(
            id: "gemini-\(identifierPart(bucket.modelId))-\(identifierPart(tokenType))",
            kind: .usage,
            value: .number(Decimal((1 - bucket.remainingFraction) * 100))
        )
    }

    private static func tokenTypeLabel(_ tokenType: String?) -> String {
        switch tokenType?.uppercased() {
        case "REQUESTS":
            String(displayLocalized: "Requests", bundle: .module)
        case "INPUT_TOKENS":
            String(displayLocalized: "Input tokens", bundle: .module)
        case "OUTPUT_TOKENS":
            String(displayLocalized: "Output tokens", bundle: .module)
        default:
            String(displayLocalized: "Quota", bundle: .module)
        }
    }

    private func identifierPart(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber ? String(character) : "-"
        }.joined()
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct GeminiMappedBucket: Sendable {
    let modelId: String
    let tokenType: String?
    let remainingFraction: Double
    let resetDate: Date?
    let remainingAmount: String?

    static func order(_ lhs: GeminiMappedBucket, _ rhs: GeminiMappedBucket) -> Bool {
        let leftModel = lhs.modelId.lowercased()
        let rightModel = rhs.modelId.lowercased()
        if leftModel != rightModel {
            return leftModel < rightModel
        }
        return (lhs.tokenType ?? "").lowercased() < (rhs.tokenType ?? "").lowercased()
    }

    static func constrainedOrder(_ lhs: GeminiMappedBucket, _ rhs: GeminiMappedBucket) -> Bool {
        if lhs.remainingFraction != rhs.remainingFraction {
            return lhs.remainingFraction < rhs.remainingFraction
        }
        return order(lhs, rhs)
    }
}

private actor GeminiFetchCoordinator {
    private var inFlight: Task<ProviderQuota, Error>?
    private let timeout: TimeInterval

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func fetch(
        _ operation: @escaping @Sendable () async throws -> ProviderQuota
    ) async throws -> ProviderQuota {
        if let inFlight {
            return try await inFlight.value
        }
        let timeoutInterval = timeout
        let task = Task {
            try await withThrowingTaskGroup(of: ProviderQuota.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(
                        nanoseconds: UInt64(timeoutInterval * 1_000_000_000)
                    )
                    throw GeminiCLIError.timeout
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else {
                    throw GeminiCLIError.internalInconsistency
                }
                return result
            }
        }
        inFlight = task
        defer { inFlight = nil }
        do {
            return try await task.value
        } catch {
            task.cancel()
            throw error
        }
    }
}
