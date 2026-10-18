import Core
import Foundation

enum CodexCreditsBalance: Equatable, Sendable {
    case amount(UsageBalance.Amount)
    case unparseable(String)
}

extension OpenAICodexProvider {
    static let creditsLineId = "credits"
    /// The backend sends 10 decimals. A resolution taken from each string would
    /// change between reads and restart the forecast.
    static let creditsResolution = Decimal(sign: .plus, exponent: -10, significand: 1)

    /// Matches the Codex CLI: no credits unless the account has them or they
    /// are unlimited.
    func creditsBalance(for credits: CodexCredits?) -> CodexCreditsBalance? {
        guard let credits, credits.hasCredits != false || credits.unlimited == true else {
            return nil
        }
        if credits.unlimited == true {
            return .amount(.unlimited)
        }
        guard let balance = credits.balance else {
            return nil
        }
        return Self.decimal(fromBalance: balance).map { .amount(.finite($0)) } ?? .unparseable(balance)
    }

    func creditsLine(for balance: CodexCreditsBalance) -> UsageLine {
        let label = DisplayText { String(displayLocalized: "Credits", bundle: .module) }
        return switch balance {
        case let .amount(amount):
            UsageLine(
                label: label,
                balance: UsageBalance(amount: amount, unit: .credits),
                id: Self.creditsLineId,
                fallbackForLimitGroup: Self.subscriptionLimitGroup
            )
        case let .unparseable(raw):
            UsageLine(
                label: label,
                details: [UsageDetail(
                    label: DisplayText { String(displayLocalized: "Balance", bundle: .module) },
                    value: DisplayText(verbatim: raw)
                )],
                id: Self.creditsLineId,
                fallbackForLimitGroup: Self.subscriptionLimitGroup
            )
        }
    }

    func creditsMetric(for balance: CodexCreditsBalance, receivedAt: Date) -> ProviderActivityMetric? {
        switch balance {
        case let .amount(.finite(amount)):
            ProviderActivityMetric(
                id: Self.creditsLineId,
                kind: .credits,
                value: .number(amount),
                forecastDescriptor: AllowanceForecastDescriptor(
                    accounting: .balance,
                    unit: .credits,
                    resolution: Self.creditsResolution,
                    timing: .receipt(receivedAt),
                    usageLineId: Self.creditsLineId
                )
            )
        case .amount(.unlimited):
            ProviderActivityMetric(id: Self.creditsLineId, kind: .credits, value: .discrete("unlimited"))
        case .unparseable:
            nil
        }
    }

    /// `Decimal(string:)` stops at the first character it cannot read, so
    /// "1,159.57" would become 1.
    private static func decimal(fromBalance balance: String) -> Decimal? {
        let scanner = Scanner(string: balance)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let value = scanner.scanDecimal(), scanner.isAtEnd else {
            return nil
        }
        return value
    }
}
