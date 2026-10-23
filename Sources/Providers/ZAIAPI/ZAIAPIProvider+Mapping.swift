import Core
import Foundation

extension ZAIAPIProvider {
    /// The app shows currency to two decimals, so less than a cent would read
    /// as zero spend.
    static let minimumShownSpend = Decimal(sign: .plus, exponent: -2, significand: 1)

    func map(_ balance: ZAIAPIBalance, currency: String, receivedAt: Date) -> ProviderQuota {
        let available = balance.availableBalance ?? balance.balance
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: headline(available: available, currency: currency),
            lines: lines(for: balance, available: available, currency: currency),
            lastUpdated: receivedAt,
            activityObservation: activityObservation(for: balance),
            headlineUsageLineId: available == nil ? nil : Self.availableBalanceLineId
        )
    }

    /// Spend only grows with use, so top-ups and grants never read as activity.
    private func activityObservation(for balance: ZAIAPIBalance) -> ProviderActivityObservation {
        ProviderActivityObservation(
            metrics: balance.totalSpendAmount.map {
                [ProviderActivityMetric(id: Self.totalSpendLineId, kind: .usage, value: .number($0))]
            } ?? [],
            freshness: .fresh
        )
    }

    private func lines(for balance: ZAIAPIBalance, available: Decimal?, currency: String) -> [UsageLine] {
        let candidates = [
            (
                id: Self.availableBalanceLineId,
                label: DisplayText { String(displayLocalized: "Available balance", bundle: .module) },
                amount: available
            ),
            (
                id: Self.frozenBalanceLineId,
                label: DisplayText { String(displayLocalized: "Frozen", bundle: .module) },
                amount: balance.frozenBalance.flatMap { $0 == 0 ? nil : $0 }
            ),
            (
                id: Self.totalSpendLineId,
                label: DisplayText { String(displayLocalized: "Spent to date", bundle: .module) },
                amount: balance.totalSpendAmount.flatMap { $0 >= Self.minimumShownSpend ? $0 : nil }
            ),
        ]
        return candidates.compactMap { candidate in
            candidate.amount.map {
                UsageLine(
                    label: candidate.label,
                    balance: UsageBalance(amount: .finite($0), unit: .currency(currency)),
                    id: candidate.id
                )
            }
        }
    }

    private func headline(available: Decimal?, currency: String) -> DisplayText {
        guard let available else {
            return DisplayText { String(displayLocalized: "No data", bundle: .module) }
        }
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
