import Foundation

/// An amount that remains. `UsageLine.used` and `UsageLine.total` measure
/// consumption instead.
public struct UsageBalance: Equatable, Sendable {
    public enum Amount: Equatable, Sendable {
        case finite(Decimal)
        case unlimited
    }

    public enum Unit: Equatable, Sendable {
        /// An ISO 4217 code.
        case currency(String)
        case credits
    }

    public let amount: Amount
    public let unit: Unit

    public init(amount: Amount, unit: Unit) {
        self.amount = amount
        self.unit = unit
    }
}
