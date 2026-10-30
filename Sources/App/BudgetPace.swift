import Core
import Foundation

struct BudgetPace: Equatable {
    enum Allowance: Equatable {
        case perDay(percentage: Double)
        case untilReset(percentage: Double)

        var percentage: Double {
            switch self {
            case let .perDay(percentage): percentage
            case let .untilReset(percentage): percentage
            }
        }
    }

    struct Configuration: Equatable {
        let windowDuration: TimeInterval
        let segmentDuration: TimeInterval

        var dividerFractions: [Double] {
            stride(from: segmentDuration, to: windowDuration, by: segmentDuration)
                .map { $0 / windowDuration }
        }
    }

    private static let day: TimeInterval = 24 * 60 * 60

    static func configuration(for windowDuration: TimeInterval) -> Configuration? {
        if windowDuration == UsageWindowDuration.week {
            return Configuration(windowDuration: windowDuration, segmentDuration: day)
        }
        if UsageWindowDuration.calendarMonths.contains(windowDuration) {
            return Configuration(windowDuration: windowDuration, segmentDuration: 7 * day)
        }
        return nil
    }

    let configuration: Configuration
    let usedPercentage: Double
    let usedPercentageFractionLength: Int
    let remainingPercentage: Double
    let usedFraction: Double
    let elapsedFraction: Double
    let remainingTime: TimeInterval
    let allowance: Allowance
    let warningBoundary: Double
    let tier: QuotaStatusResolver.Tier

    init?(line: UsageLine, now: Date) {
        guard let reportedPercentage = QuotaStatusResolver.percentage(for: line),
              reportedPercentage.isFinite,
              let resetDate = line.resetDate,
              let windowDuration = line.windowDuration,
              let configuration = Self.configuration(for: windowDuration)
        else {
            return nil
        }

        let remainingTime = resetDate.timeIntervalSince(now)
        guard remainingTime > 0, remainingTime <= configuration.windowDuration else {
            return nil
        }

        let usedPercentage = min(max(reportedPercentage, 0), 100)
        let usedFraction = usedPercentage / 100
        let elapsedFraction = min(max(1 - remainingTime / configuration.windowDuration, 0), 1)
        let remainingPercentage = max(100 - usedPercentage, 0)

        self.configuration = configuration
        self.usedPercentage = usedPercentage
        usedPercentageFractionLength = line.percentageFractionLength
        self.remainingPercentage = remainingPercentage
        self.usedFraction = usedFraction
        self.elapsedFraction = elapsedFraction
        self.remainingTime = remainingTime

        allowance = remainingTime >= Self.day
            ? .perDay(percentage: remainingPercentage / (remainingTime / Self.day))
            : .untilReset(percentage: remainingPercentage)
        warningBoundary = min(elapsedFraction * 100 + allowance.percentage, 100)

        if usedPercentage >= 100 {
            tier = .critical
        } else if usedPercentage <= warningBoundary + 1 {
            tier = .good
        } else {
            tier = .warn
        }
    }
}
