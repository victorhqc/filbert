import Foundation

public extension UsageWindowDuration {
    static let calendarMonths: ClosedRange<TimeInterval> = 28 * 24 * 60 * 60 ... 31 * 24 * 60 * 60

    /// Monthly plans anchor each period to the subscription's UTC day and
    /// time, capped at the month's last day. A reset on a month's last day fits
    /// several subscription days, so the period starts at the latest of them.
    static func calendarMonth(endingAt resetsAt: Date) -> TimeInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: resetsAt),
              let daysInMonth = calendar.range(of: .day, in: .month, for: resetsAt)?.count,
              let daysInPreviousMonth = calendar.range(of: .day, in: .month, for: previousMonth)?.count
        else {
            return nil
        }
        let resetDay = calendar.component(.day, from: resetsAt)
        let startDay = resetDay == daysInMonth ? daysInPreviousMonth : min(resetDay, daysInPreviousMonth)
        return TimeInterval(daysInPreviousMonth - startDay + resetDay) * 24 * 60 * 60
    }
}
