import Core
import Foundation

/// Provider-owned metadata and resources for Cursor (providers 07).
///
/// Reads Cursor subscription + on-demand spend from the user's locally stored
/// Cursor auth token and displays the current billing-cycle usage as
/// `ProviderQuota` lines. The provider is `.apiKeyFree`: the user never pastes
/// a key — filbert reads the session Cursor's own apps created locally.
public struct CursorProvider: AIProvider {
    public static let providerId = "cursor"
    public static let providerName = "Cursor"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(
        localized: "Monitor subscription and on-demand spend"
    )
    public static let baseURL = URL(string: "https://api2.cursor.sh")!
    public static let authShape: ProviderAuth.Shape = .apiKeyFree
    public static let setupHelp = ProviderSetupHelp(
        linkLabel: String(localized: "Sign in to Cursor"),
        url: URL(string: "https://docs.cursor.com/en/cli/reference/authentication")!
    )

    private let locator: CursorLocator
    private let tokenStore: CursorTokenStore
    private let session: URLSession

    public init() {
        self.init(
            locator: CursorLocator(),
            tokenStore: CursorTokenStore(),
            session: .shared
        )
    }

    init(locator: CursorLocator, tokenStore: CursorTokenStore, session: URLSession) {
        self.locator = locator
        self.tokenStore = tokenStore
        self.session = session
    }

    // MARK: - Configuration (providers 07 AC10)

    public func isConfigured() -> Bool {
        tokenStore.load() != nil || locator.resolve() != nil
    }

    public func currentSetupState() async -> ProviderState? {
        if tokenStore.load() != nil {
            return nil
        }

        // No token — distinguish binary-present from binary-missing so the
        // Settings link targets the right action (providers 07 AC10).
        if locator.resolve() != nil {
            return .setup(String(localized: "Sign in to Cursor"))
        }
        return .setup(String(
            localized: "Cursor CLI not installed — run `agent login`, or sign in to the Cursor app."
        ))
    }

    // MARK: - Fetch (providers 07 AC5/AC6)

    public func fetchQuota(auth _: ProviderAuth, baseURL: URL) async throws -> ProviderQuota {
        guard let pair = tokenStore.load() else {
            throw CursorError.missingToken
        }

        let accessToken = try await tokenStore.ensureValidAccessToken(pair)

        // ── AC6: Connect-RPC call ──
        let endpoint = baseURL
            .appendingPathComponent("aiserver.v1.DashboardService")
            .appendingPathComponent("GetCurrentPeriodUsage")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CursorError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorError.network(URLError(.badServerResponse))
        }

        // ── AC10: typed errors for non-200 ──
        guard httpResponse.statusCode == 200 else {
            throw CursorError.http(httpResponse.statusCode)
        }

        let usageResponse: CursorUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        } catch {
            throw CursorError.decoding(error)
        }

        return map(usageResponse)
    }

    // MARK: - Mapping (providers 07 AC7–AC9)

    func map(_ response: CursorUsageResponse) -> ProviderQuota {
        let resetDate = Self.dateFromMsString(response.billingCycleEnd)
        let plan = normalizedPlan(from: response)
        var lines: [UsageLine] = []

        // ── AC7: plan usage → percentage + reset UsageLines ──
        if let plan {
            lines.append(contentsOf: planLines(plan, resetDate: resetDate))
        }

        // ── AC8: on-demand and pooled spend → currency UsageLines ──
        if let onDemand = normalizedOnDemand(from: response) {
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
            lastUpdated: Date()
        )
    }

    // MARK: Plan usage lines (AC7)

    private func planLines(_ plan: PlanData, resetDate: Date?) -> [UsageLine] {
        var lines: [UsageLine] = []

        var details: [UsageDetail] = []
        if let autoPercent = plan.autoPercentUsed {
            details.append(UsageDetail(
                label: String(localized: "Auto"),
                value: String(format: "%.0f%%", autoPercent)
            ))
        }
        if let apiPercent = plan.apiPercentUsed {
            details.append(UsageDetail(
                label: String(localized: "API"),
                value: String(format: "%.0f%%", apiPercent)
            ))
        }

        lines.append(UsageLine(
            label: String(localized: "Included usage"),
            used: plan.includedSpend.map { Double($0) / 100 },
            total: plan.limit.map { Double($0) / 100 },
            percentage: plan.totalPercentUsed,
            unit: "USD",
            resetDate: resetDate,
            details: details.isEmpty ? nil : details
        ))

        // Bonus credits — shown as the bonus amount when present and positive.
        if let bonus = plan.bonusSpend, bonus > 0 {
            lines.append(UsageLine(
                label: String(localized: "Bonus credits"),
                used: nil,
                total: Double(bonus) / 100,
                unit: "USD",
                resetDate: resetDate
            ))
        }

        return lines
    }

    // MARK: On-demand line (AC8)

    private func onDemandLine(_ onDemand: OnDemandData) -> UsageLine? {
        // Absent or zero-limit on-demand produces no line (providers 07 AC8).
        guard let limit = onDemand.limit, limit > 0 else { return nil }
        return UsageLine(
            label: String(localized: "On-demand spend"),
            used: onDemand.used.map { Double($0) / 100 },
            total: Double(limit) / 100,
            unit: "USD"
        )
    }

    // MARK: Pooled line (AC8)

    private func pooledLine(_ spend: CursorSpendLimitUsage) -> UsageLine? {
        guard let limit = spend.pooledLimit, limit > 0 else { return nil }
        let used = spend.pooledUsed ?? 0
        let remaining = spend.pooledRemaining ?? 0
        return UsageLine(
            label: String(localized: "Pooled spend"),
            used: Double(used) / 100,
            total: Double(used + remaining) / 100,
            unit: "USD"
        )
    }

    // MARK: Headline (AC9)

    private func computeHeadline(
        response: CursorUsageResponse,
        plan: PlanData?,
        resetDate: Date?
    ) -> String {
        if response.isUnlimited == true {
            return String(localized: "Unlimited")
        }

        guard let plan, let limit = plan.limit, limit > 0 else {
            return String(localized: "No data")
        }

        let used = plan.includedSpend ?? 0
        let remainingDollars = Double(limit - used) / 100
        let formatted = Self.currencyFormatter().string(from: NSNumber(value: remainingDollars))
            ?? String(remainingDollars)
        let amountLeft = String(localized: "\(formatted) left")

        if let resetDate {
            return "\(amountLeft) · \(QuotaFormatting.countdown(to: resetDate))"
        }
        return amountLeft
    }

    // MARK: - Normalization

    /// Unifies the new `planUsage` shape and the legacy `individualUsage.plan`
    /// shape into one model (providers 07 AC7).
    private func normalizedPlan(from response: CursorUsageResponse) -> PlanData? {
        if let plan = response.planUsage {
            return PlanData(
                totalPercentUsed: plan.totalPercentUsed,
                includedSpend: plan.includedSpend,
                limit: plan.limit,
                bonusSpend: plan.bonusSpend,
                autoPercentUsed: plan.autoPercentUsed,
                apiPercentUsed: plan.apiPercentUsed
            )
        }
        if let legacy = response.individualUsage?.plan {
            return PlanData(
                totalPercentUsed: legacy.totalPercentUsed,
                includedSpend: legacy.used,
                limit: legacy.limit,
                bonusSpend: nil,
                autoPercentUsed: nil,
                apiPercentUsed: nil
            )
        }
        return nil
    }

    private func normalizedOnDemand(from response: CursorUsageResponse) -> OnDemandData? {
        if let spend = response.spendLimitUsage {
            return OnDemandData(
                used: spend.individualUsed,
                limit: spend.individualLimit
            )
        }
        if let legacy = response.individualUsage?.onDemand {
            return OnDemandData(used: legacy.used, limit: legacy.limit)
        }
        return nil
    }

    // MARK: - Helpers

    private static func currencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }

    /// Converts a unix-milliseconds string to `Date` (providers 07 Context).
    private static func dateFromMsString(_ milliseconds: String?) -> Date? {
        guard let milliseconds, let epoch = TimeInterval(milliseconds) else { return nil }
        return Date(timeIntervalSince1970: epoch / 1000)
    }
}

// MARK: - Normalized models

private struct PlanData {
    let totalPercentUsed: Double?
    let includedSpend: Int?
    let limit: Int?
    let bonusSpend: Int?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
}

private struct OnDemandData {
    let used: Int?
    let limit: Int?
}

// MARK: - Wire types (providers 07 AC7/AC8)

/// Envelope for `GetCurrentPeriodUsage` (providers 07 AC7). Tolerant of
/// unknown fields and missing optionals (providers 07 AC7).
struct CursorUsageResponse: Decodable, Sendable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let isUnlimited: Bool?
    let planUsage: CursorPlanUsage?
    let spendLimitUsage: CursorSpendLimitUsage?
    /// Legacy shape tolerated for older API responses (providers 07 AC7).
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
