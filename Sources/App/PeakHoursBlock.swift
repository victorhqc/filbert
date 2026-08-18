import Core
import Foundation
import SwiftUI

struct PeakHoursBlock: View {
    let config: PeakHoursConfig

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            pricingContent(at: timeline.date)
        }
    }

    private func pricingContent(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Peak hours"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(localWindowLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
            if config.isScheduleActive(at: date) {
                activePricingStatus(at: date)
            } else {
                upcomingPricingStatus
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func activePricingStatus(at date: Date) -> some View {
        let inPeak = config.isInPeak(at: date)
        return HStack(spacing: 4) {
            Circle()
                .fill(inPeak ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(inPeak
                ? String(localized: "In peak")
                : String(localized: "Off peak"))
                .font(.caption2)
                .fontWeight(.medium)
            Spacer()
            if let rate = config.rate(at: date) {
                Text(PeakHoursPresentation.rateText(for: rate))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    private var upcomingPricingStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
            Text(String(localized: "Upcoming pricing"))
                .font(.caption2)
                .fontWeight(.medium)
            Spacer()
            if let effectiveDate = config.effectiveDate {
                Text(effectiveDateLabel(effectiveDate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var localWindowLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let windows = config.windows.map { window in
            let localStart = peakWindowBoundary(hour: window.startHour)
            let localEnd = peakWindowBoundary(hour: window.endHour)
            let times = "\(formatter.string(from: localStart))–\(formatter.string(from: localEnd))"
            guard let days = window.weekdays.flatMap(PeakHoursPresentation.weekdayRangeText) else {
                return times
            }
            return String.localizedStringWithFormat(String(localized: "%1$@ %2$@"), days, times)
        }
        let localizedWindows = ListFormatter.localizedString(byJoining: windows)
        return String.localizedStringWithFormat(
            String(localized: "%@ (your time)"),
            localizedWindows
        )
    }

    private func effectiveDateLabel(_ effectiveDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return String.localizedStringWithFormat(
            String(localized: "Effective %@"),
            formatter.string(from: effectiveDate)
        )
    }

    private func peakWindowBoundary(hour: Int) -> Date {
        guard let timeZone = config.timeZone else { return Date() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        var components = DateComponents()
        components.year = today.year
        components.month = today.month
        components.day = today.day
        components.hour = hour
        components.minute = 0
        components.timeZone = timeZone
        return calendar.date(from: components) ?? Date()
    }
}
