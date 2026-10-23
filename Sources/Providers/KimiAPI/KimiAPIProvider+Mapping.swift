import Core
import Foundation

extension KimiAPIProvider {
    func map(_ balance: KimiBalance, currency: String, receivedAt: Date) -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline(available: balance.availableBalance, currency: currency),
            lines: lines(for: balance, currency: currency),
            lastUpdated: receivedAt,
            activityObservation: activityObservation(for: balance),
            headlineUsageLineId: Self.availableBalanceLineId
        )
    }

    /// Every charge lowers the available balance. Kimi splits a charge across
    /// vouchers and cash, so tracking them too would count one charge twice.
    private func activityObservation(for balance: KimiBalance) -> ProviderActivityObservation {
        ProviderActivityObservation(
            metrics: [
                ProviderActivityMetric(
                    id: Self.availableBalanceLineId,
                    kind: .credits,
                    value: .number(balance.availableBalance)
                ),
            ],
            freshness: .fresh
        )
    }

    /// A component equal to the available balance repeats it, so only the
    /// available line stays.
    private func lines(for balance: KimiBalance, currency: String) -> [UsageLine] {
        let available = line(
            id: Self.availableBalanceLineId,
            label: DisplayText { String(displayLocalized: "Available balance", bundle: .module) },
            amount: balance.availableBalance,
            currency: currency
        )
        let components = [
            (
                id: Self.voucherBalanceLineId,
                label: DisplayText { String(displayLocalized: "Voucher balance", bundle: .module) },
                amount: balance.voucherBalance
            ),
            (
                id: Self.cashBalanceLineId,
                label: DisplayText { String(displayLocalized: "Cash balance", bundle: .module) },
                amount: balance.cashBalance
            ),
        ]
        .filter { $0.amount != 0 && $0.amount != balance.availableBalance }
        .map { line(id: $0.id, label: $0.label, amount: $0.amount, currency: currency) }

        return [available] + components
    }

    private func line(id: String, label: DisplayText, amount: Decimal, currency: String) -> UsageLine {
        UsageLine(
            label: label,
            balance: UsageBalance(amount: .finite(amount), unit: .currency(currency)),
            id: id
        )
    }

    private func headline(available: Decimal, currency: String) -> DisplayText {
        guard available > 0 else {
            return DisplayText { String(displayLocalized: "No balance available", bundle: .module) }
        }
        return DisplayText {
            let amount = Self.currencyFormatter(currencyCode: currency)
                .string(from: NSDecimalNumber(decimal: available)) ?? "\(available)"
            return String(displayLocalized: "\(amount) left", bundle: .module)
        }
    }

    private static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = DisplayLanguage.locale
        formatter.currencyCode = currencyCode
        return formatter
    }
}
