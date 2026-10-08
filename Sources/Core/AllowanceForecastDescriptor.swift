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
