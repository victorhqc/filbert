import Core
import Foundation

extension OpenCodeGoProvider {
    static let rollingWindowLineId = "rolling-window-usage"
    static let weeklyWindowLineId = "weekly-window-usage"
    static let monthlyWindowLineId = "monthly-window-usage"
    /// Any of the three windows blocks usage once it is full.
    static let subscriptionLimitGroup = "subscription"

    private struct Window {
        let id: String
        let label: DisplayText
        let duration: TimeInterval?
        let usage: OpenCodeGoUsageWindow
        /// `nil` for the rolling window, which slides with the latest usage.
        let periodLength: TimeInterval?
    }

    func map(_ response: OpenCodeGoUsageResponse, receivedAt: Date) -> ProviderQuota {
        let usage = response.usage
        let monthLength = UsageWindowDuration.calendarMonth(endingAt: usage.monthly.resetsAt)
        let windows = [
            Window(
                id: Self.rollingWindowLineId,
                label: DisplayText { String(displayLocalized: "5-hour window", bundle: .module) },
                duration: UsageWindowDuration.fiveHours,
                usage: usage.rolling,
                periodLength: nil
            ),
            Window(
                id: Self.weeklyWindowLineId,
                label: DisplayText { String(displayLocalized: "Weekly", bundle: .module) },
                duration: UsageWindowDuration.week,
                usage: usage.weekly,
                periodLength: UsageWindowDuration.week
            ),
            Window(
                id: Self.monthlyWindowLineId,
                label: DisplayText { String(displayLocalized: "Monthly", bundle: .module) },
                duration: monthLength,
                usage: usage.monthly,
                periodLength: monthLength
            ),
        ]

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: DisplayText { String(displayLocalized: "OpenCode Go usage", bundle: .module) },
            lines: windows.map { window in
                UsageLine(
                    label: window.label,
                    percentage: window.usage.percent,
                    resetDate: window.usage.resetsAt,
                    windowDuration: window.duration,
                    details: details(for: window.usage.status),
                    id: window.id,
                    limitGroup: Self.subscriptionLimitGroup
                )
            },
            lastUpdated: receivedAt,
            // Each request reads the live usage.
            activityObservation: ProviderActivityObservation(
                metrics: windows.map { metric(for: $0, receivedAt: receivedAt) },
                freshness: .fresh
            )
        )
    }

    private func metric(for window: Window, receivedAt: Date) -> ProviderActivityMetric {
        ProviderActivityMetric(
            id: window.id,
            kind: .usage,
            value: .number(Decimal(window.usage.percent)),
            forecastDescriptor: window.periodLength.map { length in
                AllowanceForecastDescriptor(
                    accounting: .fixedPeriod(limit: 100, resetsAt: window.usage.resetsAt, length: length),
                    unit: .percentagePoints,
                    resolution: 1,
                    timing: .receipt(receivedAt),
                    usageLineId: window.id
                )
            }
        )
    }

    private func details(for status: String) -> [UsageDetail]? {
        switch status {
        case "ok":
            nil
        case "rate-limited":
            [UsageDetail(
                label: DisplayText { String(displayLocalized: "Status", bundle: .module) },
                value: DisplayText { String(displayLocalized: "Rate limited", bundle: .module) }
            )]
        default:
            [UsageDetail(
                label: DisplayText { String(displayLocalized: "Status", bundle: .module) },
                value: DisplayText { String(displayLocalized: "Unknown status", bundle: .module) }
            )]
        }
    }
}
