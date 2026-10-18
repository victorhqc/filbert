import Core
import Foundation

enum CoarseDurationFormatting {
    private static let day: TimeInterval = 24 * 60 * 60
    private static let week: TimeInterval = 7 * day

    static func string(
        from interval: TimeInterval,
        unitsStyle: DateComponentsFormatter.UnitsStyle = .abbreviated
    ) -> String {
        let formatter = displayFormatter()
        // `.weekOfYear` throws NSInternalInconsistencyException. Only
        // `.weekOfMonth` works.
        formatter.allowedUnits = interval >= week
            ? [.weekOfMonth, .day]
            : interval >= day ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = unitsStyle
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: interval) ?? ""
    }

    static func evidenceSpan(_ interval: TimeInterval) -> String {
        let hour: TimeInterval = 60 * 60
        let rounded = interval >= hour
            ? (interval / hour).rounded() * hour
            : max((interval / 60).rounded(), 1) * 60
        let formatter = displayFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        return formatter.string(from: rounded) ?? ""
    }

    private static func displayFormatter() -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = DisplayLanguage.locale
        formatter.calendar = calendar
        return formatter
    }
}
