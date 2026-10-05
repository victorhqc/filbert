@testable import Core
import Foundation
import XCTest

class SmartRefreshPolicyTestCase: XCTestCase {
    let quietWindow: TimeInterval = 300

    func quota(
        usage: Double = 10,
        availability: ProviderAvailability? = nil,
        metrics: [ProviderActivityMetric]? = nil,
        observation: ProviderActivityObservation? = ProviderActivityObservation(),
        providerName: String = "Provider",
        headline: String = "Headline",
        lines: [UsageLine] = [UsageLine(label: "Usage", percentage: 10)],
        lastUpdated: Date = Date(),
        error: String? = nil,
        isStale: Bool = false,
        peakHoursConfig: PeakHoursConfig? = nil
    ) -> ProviderQuota {
        let resolvedObservation = observation.map { _ in
            ProviderActivityObservation(
                metrics: metrics ?? [metric(id: "usage", kind: .usage, value: Decimal(usage))],
                availability: availability
            )
        }
        return ProviderQuota(
            providerId: "provider",
            providerName: providerName,
            headline: headline,
            lines: lines,
            lastUpdated: lastUpdated,
            error: error,
            isStale: isStale,
            activityObservation: resolvedObservation,
            peakHoursConfig: peakHoursConfig
        )
    }

    func metric(
        id: String,
        kind: ProviderActivityMetric.Kind,
        value: Decimal
    ) -> ProviderActivityMetric {
        ProviderActivityMetric(id: id, kind: kind, value: .number(value))
    }

    func presentationQuota(isUpdated: Bool) -> ProviderQuota {
        quota(
            usage: 10,
            providerName: isUpdated ? "Second name" : "First name",
            headline: isUpdated ? "Second headline" : "First headline",
            lines: presentationLines(isUpdated: isUpdated),
            lastUpdated: Date(timeIntervalSince1970: isUpdated ? 2 : 1),
            error: isUpdated ? nil : "Old error",
            isStale: !isUpdated,
            peakHoursConfig: presentationPeakHours(isUpdated: isUpdated)
        )
    }

    func presentationLines(isUpdated: Bool) -> [UsageLine] {
        if isUpdated {
            return [
                UsageLine(
                    label: "Localized usage",
                    used: 9,
                    total: 100,
                    percentage: 90,
                    unit: "tokens",
                    resetDate: Date(timeIntervalSince1970: 200),
                    details: [
                        UsageDetail(label: "B", value: "2"),
                        UsageDetail(label: "A", value: "updated"),
                    ]
                ),
                UsageLine(label: "Additional line", percentage: 50),
            ]
        }
        return [
            UsageLine(
                label: "Usage",
                used: 1,
                total: 10,
                percentage: 10,
                unit: "requests",
                resetDate: Date(timeIntervalSince1970: 100),
                details: [UsageDetail(label: "A", value: "1")]
            ),
        ]
    }

    func presentationPeakHours(isUpdated: Bool) -> PeakHoursConfig {
        PeakHoursConfig(
            timeZone: TimeZone(identifier: isUpdated ? "Asia/Shanghai" : "UTC"),
            windows: [
                PeakHoursWindow(
                    startHour: isUpdated ? 14 : 1,
                    endHour: isUpdated ? 18 : 2
                ),
            ],
            peakMultiplier: isUpdated ? 4 : 3,
            offPeakMultiplier: isUpdated ? 1 : 2
        )
    }
}
