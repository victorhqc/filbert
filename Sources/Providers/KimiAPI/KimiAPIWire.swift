import Foundation

struct KimiBalanceResponse: Decodable {
    let code: Int
    let status: Bool?
    let data: KimiBalance?
}

struct KimiBalance: Decodable {
    let availableBalance: Decimal
    let voucherBalance: Decimal
    let cashBalance: Decimal

    enum CodingKeys: String, CodingKey {
        case availableBalance = "available_balance"
        case voucherBalance = "voucher_balance"
        case cashBalance = "cash_balance"
    }
}
