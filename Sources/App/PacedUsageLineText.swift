import Foundation

struct PacedUsageLineText: Equatable {
    let used: String
    let remainingTime: String
    let allowance: String
    /// Read after the line label, in order.
    let accessibilitySentences: [String]

    init(pace: BudgetPace, forecast: AllowanceForecastPresentation.Line?) {
        used = String.localizedStringWithFormat(
            String(localized: "%@%% used"),
            pace.usedPercentage.formatted(.number.precision(.fractionLength(0)))
        )
        remainingTime = String.localizedStringWithFormat(
            String(localized: "%@ left"),
            CoarseDurationFormatting.string(from: pace.remainingTime)
        )
        allowance = Self.allowanceText(pace.allowance)
        let paceStatus = switch pace.tier {
        case .good:
            String(localized: "Within current allowance")
        case .warn, .critical:
            String(localized: "Over current allowance")
        }
        accessibilitySentences = [used, remainingTime, paceStatus, allowance, forecast?.accessibilityLabel]
            .compactMap(\.self)
    }

    var accessibilityValue: String {
        AllowanceForecastPresentation.joinedSentences(accessibilitySentences)
    }

    private static func allowanceText(_ allowance: BudgetPace.Allowance) -> String {
        switch allowance {
        case let .perUnit(percentage, unit):
            let format = switch unit {
            case .day: String(localized: "About %@%%/day available")
            case .week: String(localized: "About %@%%/week available")
            }
            return String.localizedStringWithFormat(
                format,
                percentage.formatted(.number.precision(.fractionLength(1)))
            )
        case let .untilReset(percentage):
            return String.localizedStringWithFormat(
                String(localized: "%@%% available until reset"),
                percentage.formatted(.number.precision(.fractionLength(0)))
            )
        }
    }
}
