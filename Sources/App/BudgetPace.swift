import Core
import Foundation

struct BudgetPace: Equatable {
    enum AllowanceUnit: Equatable {
        case day
        case week

        var duration: TimeInterval {
            switch self {
            case .day: 24 * 60 * 60
            case .week: 7 * 24 * 60 * 60
            }
        }
    }

    enum Allowance: Equatable {
        case perUnit(percentage: Double, unit: AllowanceUnit)
        case untilReset(percentage: Double)

        var percentage: Double {
            switch self {
            case let .perUnit(percentage, _): percentage
            case let .untilReset(percentage): percentage
            }
        }
    }

    struct Configuration: Equatable {
        let windowDuration: TimeInterval
        let allowanceUnit: AllowanceUnit
        let segmentDuration: TimeInterval

        var dividerFractions: [Double] {
            stride(from: segmentDuration, to: windowDuration, by: segmentDuration)
                .map { $0 / windowDuration }
        }
    }

    static let supported: [Configuration] = [BudgetPace.weekly, BudgetPace.monthly]

    static let weekly = Configuration(
        windowDuration: UsageWindowDuration.week,
        allowanceUnit: .day,
        segmentDuration: 24 * 60 * 60
    )

    static let monthly = Configuration(
        windowDuration: UsageWindowDuration.month,
        allowanceUnit: .week,
        segmentDuration: 7 * 24 * 60 * 60
    )

    static func configuration(for windowDuration: TimeInterval) -> Configuration? {
        supported.first { $0.windowDuration == windowDuration }
    }

    let configuration: Configuration
    let usedPercentage: Double
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
        self.remainingPercentage = remainingPercentage
        self.usedFraction = usedFraction
        self.elapsedFraction = elapsedFraction
        self.remainingTime = remainingTime

        let unitDuration = configuration.allowanceUnit.duration
        allowance = remainingTime >= unitDuration
            ? .perUnit(
                percentage: remainingPercentage / (remainingTime / unitDuration),
                unit: configuration.allowanceUnit
            )
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
