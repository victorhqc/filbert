import Core
import Foundation

extension CursorProvider {
    func activityObservation(
        plan: PlanData?,
        onDemand: OnDemandData?,
        spendLimitUsage: CursorSpendLimitUsage?
    ) -> ProviderActivityObservation {
        var metrics: [ProviderActivityMetric] = []

        if let includedSpend = plan?.includedSpend {
            metrics.append(activityMetric(id: "included-usage", kind: .usage, cents: includedSpend))
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

        return ProviderActivityObservation(metrics: metrics)
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
