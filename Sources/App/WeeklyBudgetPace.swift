import Core
import Foundation

struct WeeklyBudgetPace: Equatable {
    let usedPercentage: Double
    let remainingPercentage: Double
    let usedFraction: Double
    let elapsedFraction: Double
    let remainingTime: TimeInterval
    let availablePercentagePerDay: Double?
    let warningBoundary: Double
    let tier: QuotaStatusResolver.Tier

    init?(line: UsageLine, now: Date) {
        guard let reportedPercentage = QuotaStatusResolver.percentage(for: line),
              reportedPercentage.isFinite,
              let resetDate = line.resetDate,
              let windowDuration = line.windowDuration,
              windowDuration == UsageWindowDuration.week,
              windowDuration > 0
        else {
            return nil
        }

        let remainingTime = resetDate.timeIntervalSince(now)
        guard remainingTime > 0, remainingTime <= windowDuration else {
            return nil
        }

        let usedPercentage = min(max(reportedPercentage, 0), 100)
        let usedFraction = usedPercentage / 100
        let elapsedFraction = min(max(1 - remainingTime / windowDuration, 0), 1)
        let remainingPercentage = max(100 - usedPercentage, 0)

        self.usedPercentage = usedPercentage
        self.remainingPercentage = remainingPercentage
        self.usedFraction = usedFraction
        self.elapsedFraction = elapsedFraction
        self.remainingTime = remainingTime
        availablePercentagePerDay = remainingTime >= 24 * 60 * 60
            ? remainingPercentage / (remainingTime / (24 * 60 * 60))
            : nil
        let allowance = availablePercentagePerDay ?? remainingPercentage
        warningBoundary = min(elapsedFraction * 100 + allowance, 100)

        if usedPercentage >= 100 {
            tier = .critical
        } else if usedPercentage <= warningBoundary + 1 {
            tier = .good
        } else {
            tier = .warn
        }
    }
}
