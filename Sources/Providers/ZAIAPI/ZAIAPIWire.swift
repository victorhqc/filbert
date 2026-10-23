import Foundation

/// Failures arrive as HTTP 200 with `success: false` and a business code.
struct ZAIAPIEnvelope: Decodable {
    let code: Int
    let success: Bool?
    let data: ZAIAPIBalance?
}

/// Amounts are lifetime totals in major units; zero may arrive as `0E-9`.
struct ZAIAPIBalance: Decodable {
    let balance: Decimal?
    let availableBalance: Decimal?
    let frozenBalance: Decimal?
    let totalSpendAmount: Decimal?
}
