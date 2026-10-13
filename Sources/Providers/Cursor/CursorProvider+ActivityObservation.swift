import Core
import Foundation

extension CursorProvider {
    static let includedUsageLineId = "included-usage"
    static let includedUsagePercentMetricId = "included-usage-percent"

    func activityObservation(
        plan: PlanData?,
        onDemand: OnDemandData?,
        spendLimitUsage: CursorSpendLimitUsage?,
        includedUsageForecast: AllowanceForecastDescriptor?
    ) -> ProviderActivityObservation {
        var metrics: [ProviderActivityMetric] = []

        if let includedSpend = plan?.includedSpend {
            metrics.append(activityMetric(id: Self.includedUsageLineId, kind: .usage, cents: includedSpend))
        }
        // `includedSpend` stops at `limit` while Cursor keeps serving from
        // bonus credit. Only the total percentage runs out with the plan.
        if let totalPercentUsed = plan?.totalPercentUsed, totalPercentUsed.isFinite {
            metrics.append(ProviderActivityMetric(
                id: Self.includedUsagePercentMetricId,
                kind: .usage,
                value: .number(Decimal(totalPercentUsed)),
                forecastDescriptor: includedUsageForecast
            ))
        }
        if let onDemandSpend = onDemand?.used {
            metrics.append(activityMetric(id: "on-demand-spend", kind: .usage, cents: onDemandSpend))
        }
        if let spendLimitUsage = spendLimitUsage?.pooledUsed {
            metrics.append(activityMetric(id: "spend-limit-usage", kind: .usage, cents: spendLimitUsage))
        }
        if let bonusCredits = plan?.bonusSpend, bonusCredits > 0 {
            metrics.append(activityMetric(id: "bonus-credits", kind: .credits, cents: bonusCredits))
        }

        // Each request reads the live usage.
        return ProviderActivityObservation(metrics: metrics, freshness: .fresh)
    }

    /// The legacy `individualUsage.plan` percentage has no verified meaning.
    func includedUsageForecast(for response: CursorUsageResponse, receivedAt: Date) -> AllowanceForecastDescriptor? {
        guard response.isUnlimited != true,
              response.planUsage != nil,
              let cycleStart = Self.dateFromMsString(response.billingCycleStart),
              let cycleEnd = Self.dateFromMsString(response.billingCycleEnd),
              cycleEnd > cycleStart
        else {
            return nil
        }
        return AllowanceForecastDescriptor(
            accounting: .fixedPeriod(
                limit: 100,
                resetsAt: cycleEnd,
                length: cycleEnd.timeIntervalSince(cycleStart)
            ),
            unit: .percentagePoints,
            resolution: Decimal(sign: .plus, exponent: -2, significand: 1),
            timing: .receipt(receivedAt),
            usageLineId: Self.includedUsageLineId
        )
    }

    private func activityMetric(
        id: String,
        kind: ProviderActivityMetric.Kind,
        cents: Int
    ) -> ProviderActivityMetric {
        ProviderActivityMetric(
            id: id,
            kind: kind,
            value: .number(Decimal(cents) / 100)
        )
    }
}
