import Core
import Foundation

extension ZAIProvider {
    static let fiveHourLineId = "five-hour-usage"
    static let weeklyLineId = "weekly-usage"
    static let monthlyWebToolLineId = "monthly-web-tool-usage"
    /// The five-hour and weekly windows each block usage once they are full.
    static let codingPlanLimitGroup = "coding-plan"

    func map(_ response: ZAIQuotaResponse, subscriptionVersion: String?, receivedAt: Date) -> ProviderQuota {
        let limits = response.data.limits
        var lines: [UsageLine] = []
        var fiveHourLimit: ZAILimit?
        var weeklyLimit: ZAILimit?

        for limit in limits {
            guard let window = ZAIWindowDescriptor.recognize(limit) else { continue }
            lines.append(mapLimit(limit, window: window))

            if window.isFiveHour {
                fiveHourLimit = limit
            } else if window.isWeekly {
                weeklyLimit = limit
            }
        }

        let headline = computeHeadline(
            fiveHourLimit: fiveHourLimit,
            weeklyLimit: weeklyLimit
        )
        let headlineUsageLineId = if fiveHourLimit != nil {
            Self.fiveHourLineId
        } else {
            weeklyLimit.map { _ in Self.weeklyLineId }
        }

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline,
            lines: lines,
            lastUpdated: receivedAt,
            activityObservation: activityObservation(from: limits, receivedAt: receivedAt),
            peakHoursConfig: Self.peakHoursConfig(for: limits, subscriptionVersion: subscriptionVersion),
            headlineUsageLineId: headlineUsageLineId
        )
    }

    /// A credits-shaped response identifies the credits calculation on its
    /// own; a tokens-shaped response is only legacy V2 when the subscription
    /// endpoint positively reports version "V2". Anything else — mixed
    /// shapes, unknown versions, or a failed subscription fetch — gets no
    /// pricing metadata.
    private static func peakHoursConfig(
        for limits: [ZAILimit],
        subscriptionVersion: String?
    ) -> PeakHoursConfig? {
        let types = Set(limits.map(\.type))
        let hasCreditWindows = types.contains(ZAILimitType.credits.rawValue)
        let hasTokenWindows = types.contains(ZAILimitType.tokens.rawValue)

        if hasCreditWindows, !hasTokenWindows {
            return ZAIPeakHours.credits
        }
        if hasTokenWindows, !hasCreditWindows, subscriptionVersion == "V2" {
            return ZAIPeakHours.legacyV2
        }
        return nil
    }

    private func activityObservation(from limits: [ZAILimit], receivedAt: Date) -> ProviderActivityObservation {
        let weeklyCount = limits.filter { activityMetricID(for: $0) == Self.weeklyLineId }.count
        var metrics: [ProviderActivityMetric] = []
        for limit in limits {
            guard let id = activityMetricID(for: limit) else { continue }
            let isForecast = id == Self.weeklyLineId && weeklyCount == 1
            // The coarse percentage is the base value, so each id keeps one
            // stable unit. Absolute consumption, when reported, gets a
            // distinct id so a response that drops it cannot flip the base id
            // between units and read as activity. `usage` is the allowance and
            // never counts here.
            if let percentage = limit.percentage {
                metrics.append(ProviderActivityMetric(
                    id: id,
                    kind: .usage,
                    value: .number(Decimal(percentage)),
                    forecastDescriptor: isForecast ? percentageDescriptor(for: limit, receivedAt: receivedAt) : nil
                ))
            }
            if let currentValue = limit.currentValue {
                metrics.append(ProviderActivityMetric(
                    id: "\(id)-absolute",
                    kind: .usage,
                    value: .number(Decimal(currentValue)),
                    forecastDescriptor: isForecast ? creditsDescriptor(for: limit, receivedAt: receivedAt) : nil
                ))
            }
        }
        // Each request reads the live usage.
        return ProviderActivityObservation(metrics: metrics, freshness: .fresh)
    }

    private func percentageDescriptor(for limit: ZAILimit, receivedAt: Date) -> AllowanceForecastDescriptor? {
        guard ZAILimitType(rawValue: limit.type) == .tokens else { return nil }
        return weeklyDescriptor(for: limit, allowance: 100, unit: .percentagePoints, receivedAt: receivedAt)
    }

    private func creditsDescriptor(for limit: ZAILimit, receivedAt: Date) -> AllowanceForecastDescriptor? {
        guard ZAILimitType(rawValue: limit.type) == .credits, let allowance = limit.usage, allowance > 0 else {
            return nil
        }
        return weeklyDescriptor(for: limit, allowance: Decimal(allowance), unit: .credits, receivedAt: receivedAt)
    }

    /// The weekly cycle runs 7 days from the order time, or from the last
    /// reset card, so `nextResetTime` is the only anchor.
    private func weeklyDescriptor(
        for limit: ZAILimit,
        allowance: Decimal,
        unit: AllowanceForecastDescriptor.Unit,
        receivedAt: Date
    ) -> AllowanceForecastDescriptor? {
        guard let resetsAt = limit.resetDate else { return nil }
        return AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: allowance, resetsAt: resetsAt, length: UsageWindowDuration.week),
            unit: unit,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: Self.weeklyLineId
        )
    }

    private func activityMetricID(for limit: ZAILimit) -> String? {
        switch (ZAILimitType(rawValue: limit.type), limit.unit) {
        case (.tokens, 3), (.credits, 3):
            Self.fiveHourLineId
        case (.tokens, 6), (.credits, 6):
            Self.weeklyLineId
        case (.time, 5):
            Self.monthlyWebToolLineId
        default:
            nil
        }
    }

    private func mapLimit(_ limit: ZAILimit, window: ZAIWindowDescriptor) -> UsageLine {
        // z.ai overloads these fields by limit type:
        //  - token windows (unit 3/6): only `percentage`, no usage/currentValue
        //  - credit windows (unit 3/6): `currentValue` = credits used,
        //    `usage` = the credit allowance
        //  - monthly web-tool line (unit 5): `currentValue` = actual used,
        //    `usage` = the allowance (cap), `remaining` = what's left.
        let used: Double?
        let total: Double?
        if let currentValue = limit.currentValue {
            used = currentValue
            total = limit.usage
        } else {
            used = limit.usage
            total = nil
        }

        let details = limit.usageDetails.map { details in
            details.map { detail in
                let value = if let usage = detail.usage {
                    DisplayText {
                        usage.formatted(.number.precision(.fractionLength(0)).locale(DisplayLanguage.locale))
                    }
                } else {
                    DisplayText(verbatim: "—")
                }
                return UsageDetail(label: DisplayText(verbatim: detail.modelCode), value: value)
            }
        }

        return UsageLine(
            label: window.label,
            used: used,
            total: total,
            percentage: limit.percentage,
            unit: nil,
            resetDate: limit.resetDate,
            windowDuration: window.windowDuration,
            details: details,
            id: activityMetricID(for: limit),
            limitGroup: window.isFiveHour || window.isWeekly ? Self.codingPlanLimitGroup : nil
        )
    }

    private func computeHeadline(
        fiveHourLimit: ZAILimit?,
        weeklyLimit: ZAILimit?
    ) -> DisplayText {
        let primary = fiveHourLimit ?? weeklyLimit

        if let primary, let pct = primary.percentage {
            if let resetDate = primary.resetDate {
                return DisplayText {
                    "\(QuotaFormatting.percentage(pct)) · \(QuotaFormatting.countdown(to: resetDate))"
                }
            }
            return DisplayText { QuotaFormatting.percentage(pct) }
        }

        return DisplayText { String(displayLocalized: "No data", bundle: .module) }
    }
}
