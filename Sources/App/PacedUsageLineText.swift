import Core
import Foundation

struct PacedUsageLineText: Equatable {
    let used: String
    let remainingTime: String
    let allowance: String
    /// Read after the line label, in order.
    let accessibilitySentences: [String]

    init(pace: BudgetPace, forecast: AllowanceForecastPresentation.Line?) {
        used = String.localizedStringWithFormat(
            String(displayLocalized: "%@%% used", bundle: .module),
            pace.usedPercentage.formatted(
                .number.precision(.fractionLength(pace.usedPercentageFractionLength)).locale(DisplayLanguage.locale)
            )
        )
        let leftFormat = String(displayLocalized: "%@ left", bundle: .module)
        remainingTime = String.localizedStringWithFormat(
            leftFormat,
            CoarseDurationFormatting.string(from: pace.remainingTime)
        )
        let spokenRemainingTime = String.localizedStringWithFormat(
            leftFormat,
            CoarseDurationFormatting.string(from: pace.remainingTime, unitsStyle: .full)
        )
        allowance = Self.allowanceText(pace.allowance)
        let paceStatus = switch pace.tier {
        case .good:
            String(displayLocalized: "Within current allowance", bundle: .module)
        case .warn, .critical:
            String(displayLocalized: "Over current allowance", bundle: .module)
        }
        accessibilitySentences = [used, spokenRemainingTime, paceStatus, allowance, forecast?.accessibilityLabel]
            .compactMap(\.self)
    }

    var accessibilityValue: String {
        AllowanceForecastPresentation.joinedSentences(accessibilitySentences)
    }

    private static func allowanceText(_ allowance: BudgetPace.Allowance) -> String {
        switch allowance {
        case let .perDay(percentage):
            String.localizedStringWithFormat(
                String(displayLocalized: "About %@%%/day available", bundle: .module),
                percentage.formatted(.number.precision(.fractionLength(1)).locale(DisplayLanguage.locale))
            )
        case let .untilReset(percentage):
            String.localizedStringWithFormat(
                String(displayLocalized: "%@%% available until reset", bundle: .module),
                percentage.formatted(.number.precision(.fractionLength(0)).locale(DisplayLanguage.locale))
            )
        }
    }
}
