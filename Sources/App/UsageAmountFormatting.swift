import Core
import Foundation

enum UsageAmountFormatting {
    static func string(for balance: UsageBalance, locale: Locale = .current) -> String {
        switch (balance.amount, balance.unit) {
        case (.unlimited, _):
            String(displayLocalized: "Unlimited", bundle: .module)
        case let (.finite(amount), .currency(code)):
            currency(NSDecimalNumber(decimal: amount), code: code, locale: locale)
        case let (.finite(amount), .credits):
            credits(NSDecimalNumber(decimal: amount), locale: locale)
        }
    }

    static func currency(_ amount: NSNumber, code: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: amount) ?? amount.stringValue
    }

    private static func credits(_ amount: NSNumber, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount) ?? amount.stringValue
    }
}
