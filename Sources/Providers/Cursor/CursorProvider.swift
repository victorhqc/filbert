import Core
import Foundation

public struct CursorProvider: AIProvider {
    public static let providerId = "cursor"
    public static let providerName = "Cursor"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static var providerDescription: String {
        String(displayLocalized: "Monitor subscription and on-demand spend", bundle: .module)
    }

    public static var providerDisclaimer: String? {
        String(
            displayLocalized: """
            This provider uses undocumented Cursor endpoints and may stop working if Cursor changes them.
            """,
            bundle: .module
        )
    }

    public static let baseURL = URL(string: "https://api2.cursor.sh")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static var setupHelp: ProviderSetupHelp? {
        ProviderSetupHelp(
            linkLabel: String(displayLocalized: "Sign in to Cursor", bundle: .module),
            url: URL(string: "https://cursor.com/docs/cli/reference/authentication")!
        )
    }

    private let locator: CursorLocator
    let tokenStore: CursorTokenStore
    private let session: URLSession
    private let rateLimitBackoff: CursorRateLimitBackoff
    let errorLog: ErrorLog

    public init() {
        self.init(
            locator: CursorLocator(),
            tokenStore: CursorTokenStore(),
            session: .shared,
            rateLimitBackoff: CursorRateLimitBackoff()
        )
    }

    init(
        locator: CursorLocator,
        tokenStore: CursorTokenStore,
        session: URLSession,
        rateLimitBackoff: CursorRateLimitBackoff = CursorRateLimitBackoff(),
        errorLog: ErrorLog = .shared
    ) {
        self.locator = locator
        self.tokenStore = tokenStore
        self.session = session
        self.rateLimitBackoff = rateLimitBackoff
        self.errorLog = errorLog
    }

    // MARK: - Configuration

    public func isConfigured() -> Bool {
        do {
            return try tokenStore.loadOrBootstrap() != nil
        } catch {
            recordCredentialFailure(operation: "isConfigured", error: error)
            return false
        }
    }

    public func currentSetupState() async -> ProviderState? {
        do {
            if try tokenStore.loadOrBootstrap() != nil {
                return nil
            }
        } catch CursorCredentialVaultError.unavailable {
            return missingCredentialSetupState()
        } catch {
            guard !isCredentialCancellation(error) else { return missingCredentialSetupState() }
            recordCredentialFailure(operation: "currentSetupState", error: error)
            return .error(DisplayText(describing: error))
        }

        return missingCredentialSetupState()
    }

    private func missingCredentialSetupState() -> ProviderState {
        if locator.resolve() != nil {
            return .setup(DisplayText { String(displayLocalized: "Sign in to Cursor", bundle: .module) })
        }
        return .setup(DisplayText {
            String(
                displayLocalized: "Cursor CLI not installed — run `agent login`, or sign in to the Cursor app.",
                bundle: .module
            )
        })
    }

    // MARK: - Fetch

    public func fetchQuota(auth _: ProviderAuth, baseURL: URL) async throws -> ProviderQuota {
        try await rateLimitBackoff.checkRequestAllowed()
        let pair = try loadCredentialsForRequest()

        let accessToken: String
        do {
            accessToken = try await tokenStore.ensureValidAccessToken(pair)
        } catch where isCredentialCancellation(error) {
            throw CancellationError()
        } catch let error as CursorError {
            if case .http(429) = error {
                await rateLimitBackoff.recordRateLimit()
            }
            throw error
        }

        let endpoint = baseURL
            .appendingPathComponent("aiserver.v1.DashboardService")
            .appendingPathComponent("GetCurrentPeriodUsage")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await response(for: request)
        let receivedAt = Date()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorError.network(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            await rateLimitBackoff.recordRateLimit()
            throw CursorError.http(429)
        }
        await rateLimitBackoff.recordSuccessfulResponse()

        guard httpResponse.statusCode == 200 else {
            throw CursorError.http(httpResponse.statusCode)
        }

        let usageResponse: CursorUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        } catch {
            throw CursorError.decoding(error)
        }

        return map(usageResponse, receivedAt: receivedAt)
    }

    private func loadCredentialsForRequest() throws -> CursorTokenPair {
        do {
            guard let credentials = try tokenStore.loadOrBootstrap() else {
                throw ProviderSetupError.missingCredentials
            }
            return credentials
        } catch CursorCredentialVaultError.unavailable {
            throw ProviderSetupError.missingCredentials
        } catch where isCredentialCancellation(error) {
            throw CancellationError()
        }
    }

    private func response(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CursorError.network(error)
        }
    }

    // MARK: - Mapping

    func map(_ response: CursorUsageResponse, receivedAt: Date) -> ProviderQuota {
        let resetDate = Self.dateFromMsString(response.billingCycleEnd)
        let plan = normalizedPlan(from: response)
        let onDemand = normalizedOnDemand(from: response)
        var lines: [UsageLine] = []

        if let plan {
            lines.append(contentsOf: planLines(plan, resetDate: resetDate))
        }

        if let onDemand {
            if let line = onDemandLine(onDemand) {
                lines.append(line)
            }
        }
        if let spend = response.spendLimitUsage {
            if let line = pooledLine(spend) {
                lines.append(line)
            }
        }

        let headline = computeHeadline(
            response: response,
            plan: plan,
            resetDate: resetDate
        )

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: receivedAt,
            activityObservation: activityObservation(
                plan: plan,
                onDemand: onDemand,
                spendLimitUsage: response.spendLimitUsage,
                includedUsageForecast: includedUsageForecast(for: response, receivedAt: receivedAt)
            )
        )
    }

    // MARK: Plan usage lines

    private func planLines(_ plan: PlanData, resetDate: Date?) -> [UsageLine] {
        var lines: [UsageLine] = []

        var details: [UsageDetail] = []
        if let autoPercent = plan.autoPercentUsed {
            details.append(UsageDetail(
                label: DisplayText { String(displayLocalized: "Auto", bundle: .module) },
                value: DisplayText(verbatim: String(format: "%.0f%%", autoPercent))
            ))
        }
        if let apiPercent = plan.apiPercentUsed {
            details.append(UsageDetail(
                label: DisplayText { String(displayLocalized: "API", bundle: .module) },
                value: DisplayText(verbatim: String(format: "%.0f%%", apiPercent))
            ))
        }

        lines.append(UsageLine(
            label: DisplayText { String(displayLocalized: "Included usage", bundle: .module) },
            used: plan.includedSpend.map { Double($0) / 100 },
            total: plan.limit.map { Double($0) / 100 },
            percentage: plan.totalPercentUsed,
            unit: "USD",
            resetDate: resetDate,
            details: details.isEmpty ? nil : details,
            id: Self.includedUsageLineId
        ))

        if let bonus = plan.bonusSpend, bonus > 0 {
            lines.append(UsageLine(
                label: DisplayText { String(displayLocalized: "Bonus credits", bundle: .module) },
                used: Double(bonus) / 100,
                unit: "USD",
                resetDate: resetDate
            ))
        }

        return lines
    }

    // MARK: On-demand line

    private func onDemandLine(_ onDemand: OnDemandData) -> UsageLine? {
        guard let limit = onDemand.limit, limit > 0 else { return nil }
        return UsageLine(
            label: DisplayText { String(displayLocalized: "On-demand spend", bundle: .module) },
            used: onDemand.used.map { Double($0) / 100 },
            total: Double(limit) / 100,
            unit: "USD"
        )
    }

    // MARK: Pooled line

    private func pooledLine(_ spend: CursorSpendLimitUsage) -> UsageLine? {
        guard let limit = spend.pooledLimit, limit > 0 else { return nil }
        let used = spend.pooledUsed ?? 0
        let remaining = spend.pooledRemaining ?? 0
        return UsageLine(
            label: DisplayText { String(displayLocalized: "Pooled spend", bundle: .module) },
            used: Double(used) / 100,
            total: Double(used + remaining) / 100,
            unit: "USD"
        )
    }
}

// MARK: - Headline

extension CursorProvider {
    private func computeHeadline(
        response: CursorUsageResponse,
        plan: PlanData?,
        resetDate: Date?
    ) -> DisplayText {
        if response.isUnlimited == true {
            return DisplayText { String(displayLocalized: "Unlimited", bundle: .module) }
        }

        guard let plan, let limit = plan.limit, limit > 0 else {
            return DisplayText { String(displayLocalized: "No data", bundle: .module) }
        }

        let used = plan.includedSpend ?? 0
        let remainingDollars = Double(limit - used) / 100
        return DisplayText {
            let formatted = Self.currencyFormatter().string(from: NSNumber(value: remainingDollars))
                ?? String(remainingDollars)
            let amountLeft = String(displayLocalized: "\(formatted) left", bundle: .module)
            guard let resetDate else { return amountLeft }
            return "\(amountLeft) · \(QuotaFormatting.countdown(to: resetDate))"
        }
    }
}

// MARK: - Helpers

extension CursorProvider {
    private static func currencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = DisplayLanguage.locale
        formatter.currencyCode = "USD"
        return formatter
    }

    static func dateFromMsString(_ milliseconds: String?) -> Date? {
        guard let milliseconds, let epoch = TimeInterval(milliseconds) else { return nil }
        return Date(timeIntervalSince1970: epoch / 1000)
    }
}

// MARK: - Normalized models

struct PlanData {
    let totalPercentUsed: Double?
    let includedSpend: Int?
    let limit: Int?
    let bonusSpend: Int?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
}

struct OnDemandData {
    let used: Int?
    let limit: Int?
}

// MARK: - Wire types

struct CursorUsageResponse: Decodable, Sendable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let isUnlimited: Bool?
    let planUsage: CursorPlanUsage?
    let spendLimitUsage: CursorSpendLimitUsage?
    /// Legacy shape tolerated for older API responses.
    let individualUsage: CursorIndividualUsage?
}

struct CursorPlanUsage: Decodable, Sendable {
    let totalPercentUsed: Double?
    let includedSpend: Int?
    let limit: Int?
    let bonusSpend: Int?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
}

struct CursorSpendLimitUsage: Decodable, Sendable {
    let individualUsed: Int?
    let individualLimit: Int?
    let pooledUsed: Int?
    let pooledLimit: Int?
    let pooledRemaining: Int?
}

struct CursorIndividualUsage: Decodable, Sendable {
    let plan: CursorLegacyPlan?
    let onDemand: CursorLegacyOnDemand?
}

struct CursorLegacyPlan: Decodable, Sendable {
    let used: Int?
    let limit: Int?
    let remaining: Int?
    let totalPercentUsed: Double?
}

struct CursorLegacyOnDemand: Decodable, Sendable {
    let used: Int?
    let limit: Int?
}
