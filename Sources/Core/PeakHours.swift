import Foundation

public struct PeakHoursWindow: Equatable, Sendable {
    public let startHour: Int
    public let endHour: Int
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday); nil means every day.
    public let weekdays: Set<Int>?

    public init(startHour: Int, endHour: Int, weekdays: Set<Int>? = nil) {
        self.startHour = startHour
        self.endHour = endHour
        self.weekdays = weekdays
    }
}

/// How a schedule presents its active rate: an integer billing multiplier
/// ("3×") or a fraction of the provider's standard credit rate (0.5 = 50%).
public enum PeakRatePresentation: Equatable, Sendable {
    case multiplier(Int)
    case fractionOfStandardRate(Double)
}

public struct PeakHoursConfig: Sendable {
    public let timeZone: TimeZone?
    public let windows: [PeakHoursWindow]
    public let peakRate: PeakRatePresentation
    public let offPeakRate: PeakRatePresentation
    public let promoMultiplier: Int?
    public let promoEndDate: Date?
    public let effectiveDate: Date?

    public init(
        timeZone: TimeZone?,
        windows: [PeakHoursWindow],
        peakMultiplier: Int,
        offPeakMultiplier: Int,
        promoMultiplier: Int? = nil,
        promoEndDate: Date? = nil,
        effectiveDate: Date? = nil
    ) {
        self.init(
            timeZone: timeZone,
            windows: windows,
            peakRate: .multiplier(peakMultiplier),
            offPeakRate: .multiplier(offPeakMultiplier),
            promoMultiplier: promoMultiplier,
            promoEndDate: promoEndDate,
            effectiveDate: effectiveDate
        )
    }

    public init(
        timeZone: TimeZone?,
        windows: [PeakHoursWindow],
        peakRate: PeakRatePresentation,
        offPeakRate: PeakRatePresentation,
        promoMultiplier: Int? = nil,
        promoEndDate: Date? = nil,
        effectiveDate: Date? = nil
    ) {
        self.timeZone = timeZone
        self.windows = windows
        self.peakRate = peakRate
        self.offPeakRate = offPeakRate
        self.promoMultiplier = promoMultiplier
        self.promoEndDate = promoEndDate
        self.effectiveDate = effectiveDate
    }

    public var peakMultiplier: Int? {
        guard case let .multiplier(value) = peakRate else { return nil }
        return value
    }

    public var offPeakMultiplier: Int? {
        guard case let .multiplier(value) = offPeakRate else { return nil }
        return value
    }

    public func isScheduleActive(at date: Date) -> Bool {
        guard let effectiveDate else { return true }
        return date >= effectiveDate
    }

    public func isInPeak(at date: Date) -> Bool {
        guard isScheduleActive(at: date), let timeZone else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)
        return windows.contains { window in
            hour >= window.startHour && hour < window.endHour
                && window.weekdays?.contains(weekday) ?? true
        }
    }

    public func rate(at date: Date) -> PeakRatePresentation? {
        guard isScheduleActive(at: date) else { return nil }
        if isInPeak(at: date) {
            return peakRate
        }
        if let promoEnd = promoEndDate, date < promoEnd, let promoMultiplier {
            return .multiplier(promoMultiplier)
        }
        return offPeakRate
    }

    public func multiplier(at date: Date) -> Int? {
        guard case let .multiplier(value) = rate(at: date) else { return nil }
        return value
    }
}
