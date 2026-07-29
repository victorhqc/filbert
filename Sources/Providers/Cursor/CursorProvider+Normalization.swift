import Foundation

extension CursorProvider {
    func normalizedPlan(from response: CursorUsageResponse) -> PlanData? {
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

    func normalizedOnDemand(from response: CursorUsageResponse) -> OnDemandData? {
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
}
