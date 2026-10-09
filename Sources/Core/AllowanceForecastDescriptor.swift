import Foundation

public struct AllowanceForecastDescriptor: Equatable, Sendable {
    public enum Accounting: Equatable, Sendable {
        /// The metric value is the amount consumed in the current period.
        case fixedPeriod(limit: Decimal, resetsAt: Date)
        /// The metric value is the amount remaining.
        case balance
    }

    public enum Unit: Equatable, Sendable {
        case percentagePoints
        case currency(String)
        case credits
    }

    public enum Timing: Equatable, Sendable {
        case source(Date)
        /// Use only when the provider reports no measurement time.
        case receipt(Date)

        public var date: Date {
            switch self {
            case let .source(date), let .receipt(date):
                date
            }
        }

        public var isApproximate: Bool {
            if case .receipt = self {
                return true
            }
            return false
        }
    }

    public let accounting: Accounting
    public let unit: Unit
    public let resolution: Decimal
    public let timing: Timing
    public let usageLineId: String

    public init(
        accounting: Accounting,
        unit: Unit,
        resolution: Decimal,
        timing: Timing,
        usageLineId: String
    ) {
        self.accounting = accounting
        self.unit = unit
        self.resolution = resolution
        self.timing = timing
        self.usageLineId = usageLineId
    }
}

extension AllowanceForecastDescriptor {
    /// Ignores timing, which changes on every write, and reset jitter within
    /// the tolerance.
    func describesSameAllowance(as other: Self, resetTolerance: TimeInterval) -> Bool {
        guard unit == other.unit, resolution == other.resolution, usageLineId == other.usageLineId else {
            return false
        }
        switch (accounting, other.accounting) {
        case (.balance, .balance):
            return true
        case let (.fixedPeriod(limit, resetsAt), .fixedPeriod(otherLimit, otherResetsAt)):
            return limit == otherLimit && abs(resetsAt.timeIntervalSince(otherResetsAt)) <= resetTolerance
        case (.balance, .fixedPeriod), (.fixedPeriod, .balance):
            return false
        }
    }
}
