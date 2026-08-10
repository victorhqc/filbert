import Core
import Foundation

struct WeeklyBudgetPace: Equatable {
    let usedPercentage: Double
    let remainingPercentage: Double
    let usedFraction: Double
    let elapsedFraction: Double
    let remainingTime: TimeInterval
    let availablePercentagePerDay: Double?
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

        if usedPercentage >= 100 {
            tier = .critical
        } else if usedFraction <= elapsedFraction + 0.01 {
            tier = .good
        } else {
            tier = .warn
        }
    }
}
