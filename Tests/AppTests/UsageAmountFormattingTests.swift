@testable import App
import Core
import XCTest

final class UsageAmountFormattingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        super.tearDown()
    }

    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    func testCreditsShowTwoLocalizedDecimalsWithoutASymbol() {
        let balance = credits("1159.5692275000")

        XCTAssertEqual(UsageAmountFormatting.string(for: balance, locale: english), "1,159.57")
        XCTAssertEqual(UsageAmountFormatting.string(for: balance, locale: german), "1.159,57")
    }

    func testCreditsAlwaysShowTwoDecimals() {
        XCTAssertEqual(UsageAmountFormatting.string(for: credits("80"), locale: english), "80.00")
        XCTAssertEqual(UsageAmountFormatting.string(for: credits("0"), locale: english), "0.00")
    }

    func testCurrencyUsesTheBalanceCurrencyCode() {
        let usd = currency("1159.57", code: "USD")
        let cny = currency("2.97", code: "CNY")

        XCTAssertEqual(UsageAmountFormatting.string(for: usd, locale: english), "$1,159.57")
        let germanYuan = UsageAmountFormatting.string(for: cny, locale: german)
        XCTAssertTrue(germanYuan.contains("2,97"), germanYuan)
        XCTAssertTrue(germanYuan.contains("CN¥"), germanYuan)
    }

    func testUnlimitedBalancesShowUnlimited() {
        XCTAssertEqual(UsageAmountFormatting.string(for: UsageBalance(amount: .unlimited, unit: .credits)), "Unlimited")
    }

    func testRowAmountIsTheBalanceOrAnAmountSpentWithoutALimit() {
        let balance = UsageLine(label: DisplayText(verbatim: "Credits"), balance: credits("12.5"))
        let spent = UsageLine(label: DisplayText(verbatim: "Bonus credits"), used: 20, unit: "USD")
        let limited = UsageLine(label: DisplayText(verbatim: "On-demand spend"), used: 15, total: 20, unit: "USD")
        let spentWithoutCurrency = UsageLine(label: DisplayText(verbatim: "Requests"), used: 20)

        XCTAssertEqual(QuotaStatusResolver.amountText(for: balance), UsageAmountFormatting.string(for: credits("12.5")))
        XCTAssertEqual(
            QuotaStatusResolver.amountText(for: spent),
            UsageAmountFormatting.currency(20, code: "USD")
        )
        XCTAssertNil(QuotaStatusResolver.amountText(for: limited))
        XCTAssertNil(QuotaStatusResolver.amountText(for: spentWithoutCurrency))
    }

    private func currency(_ amount: String, code: String) -> UsageBalance {
        UsageBalance(amount: .finite(Decimal(string: amount)!), unit: .currency(code))
    }

    private func credits(_ amount: String) -> UsageBalance {
        UsageBalance(amount: .finite(Decimal(string: amount)!), unit: .credits)
    }
}
