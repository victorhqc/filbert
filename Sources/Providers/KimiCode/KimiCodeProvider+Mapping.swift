import Core
import Foundation

extension KimiCodeProvider {
    static let fiveHourLineId = "five-hour-usage"
    static let weeklyLineId = "weekly-usage"
    static let monthlyLineId = "monthly-usage"
    /// Any window blocks Kimi Code once it is full.
    static let membershipLimitGroup = "membership"

    private struct Reading {
        let percentage: Double
        let resetDate: Date?
    }

    private struct Window {
        let id: String
        let label: DisplayText
        let duration: TimeInterval
        let reading: Reading
    }

    func map(_ response: KimiCodeUsagesResponse, receivedAt: Date) -> ProviderQuota {
        let windows = windows(in: response)
        let lines = windows.map { window in
            UsageLine(
                label: window.label,
                percentage: window.reading.percentage,
                resetDate: window.reading.resetDate,
                windowDuration: window.duration,
                id: window.id,
                limitGroup: Self.membershipLimitGroup
            )
        }
        // Windows are built tightest first.
        let headlineWindow = windows.first

        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline(for: headlineWindow?.reading),
            lines: lines,
            lastUpdated: receivedAt,
            activityObservation: activityObservation(for: windows),
            headlineUsageLineId: headlineWindow?.id
        )
    }

    private func windows(in response: KimiCodeUsagesResponse) -> [Window] {
        let fiveHourCounter = response.limits.first { $0.window.duration == UsageWindowDuration.fiveHours }?.detail
        let candidates = [
            (
                id: Self.fiveHourLineId,
                label: DisplayText { String(displayLocalized: "5-hour window", bundle: .module) },
                duration: UsageWindowDuration.fiveHours,
                readings: [fiveHourCounter.map(Self.reading), response.usages["limit_5h"].map(Self.reading)]
            ),
            (
                id: Self.weeklyLineId,
                label: DisplayText { String(displayLocalized: "Weekly", bundle: .module) },
                duration: UsageWindowDuration.week,
                readings: [response.usage.map(Self.reading), response.usages["limit_7d"].map(Self.reading)]
            ),
            (
                id: Self.monthlyLineId,
                label: DisplayText { String(displayLocalized: "Monthly", bundle: .module) },
                duration: UsageWindowDuration.month,
                readings: [response.usages["limit_month_total"].map(Self.reading)]
            ),
        ]
        return candidates.compactMap { candidate in
            Self.merge(candidate.readings.compactMap(\.self)).map { reading in
                Window(id: candidate.id, label: candidate.label, duration: candidate.duration, reading: reading)
            }
        }
    }

    /// The ratio map often reads 0 while the legacy counter for the same
    /// window is exhausted, and the exhausted one is enforced, so the higher
    /// reading wins.
    private static func merge(_ readings: [Reading]) -> Reading? {
        guard let highest = readings.max(by: { $0.percentage < $1.percentage }) else { return nil }
        return Reading(
            percentage: highest.percentage,
            resetDate: highest.resetDate ?? readings.lazy.compactMap(\.resetDate).first
        )
    }

    private static func reading(_ counter: KimiCodeCounter) -> Reading {
        Reading(percentage: clamped(counter.used / counter.limit * 100), resetDate: counter.resetDate)
    }

    private static func reading(_ ratio: KimiCodeRatio) -> Reading {
        Reading(percentage: clamped(ratio.usedRatio * 100), resetDate: ratio.resetDate)
    }

    private static func clamped(_ percentage: Double) -> Double {
        min(max(percentage, 0), 100)
    }

    private func headline(for reading: Reading?) -> DisplayText {
        guard let reading else {
            return DisplayText { String(displayLocalized: "No data", bundle: .module) }
        }
        let percentage = reading.percentage
        guard let resetDate = reading.resetDate else {
            return DisplayText { QuotaFormatting.percentage(percentage) }
        }
        return DisplayText {
            "\(QuotaFormatting.percentage(percentage)) · \(QuotaFormatting.countdown(to: resetDate))"
        }
    }

    private func activityObservation(for windows: [Window]) -> ProviderActivityObservation {
        let metrics = windows.map { window in
            ProviderActivityMetric(
                id: window.id,
                kind: .usage,
                value: .number(Decimal(window.reading.percentage))
            )
        }
        // Each request reads the live usage.
        return ProviderActivityObservation(metrics: metrics, freshness: .fresh)
    }
}
