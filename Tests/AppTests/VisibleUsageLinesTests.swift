@testable import App
import Core
import XCTest

final class VisibleUsageLinesTests: XCTestCase {
    func testTheCardShowsEveryLineWithSomethingToShow() {
        let lines = [
            UsageLine(label: DisplayText(verbatim: "Window"), percentage: 30),
            UsageLine(
                label: DisplayText(verbatim: "Empty credits"),
                balance: UsageBalance(amount: .finite(0), unit: .credits)
            ),
            UsageLine(
                label: DisplayText(verbatim: "Unlimited credits"),
                balance: UsageBalance(amount: .unlimited, unit: .credits)
            ),
            UsageLine(label: DisplayText(verbatim: "Bonus credits"), used: 20, unit: "USD"),
            UsageLine(
                label: DisplayText(verbatim: "Credits"),
                details: [UsageDetail(label: DisplayText(verbatim: "Credits"), value: DisplayText(verbatim: "12.5"))]
            ),
        ]

        XCTAssertEqual(visibleUsageLines(lines).map(\.label.resolved), lines.map(\.label.resolved))
    }

    func testEqualAmountsAreNoLongerMerged() {
        let lines = [
            UsageLine(label: DisplayText(verbatim: "Total balance"), balance: balance("18.50", currency: "USD")),
            UsageLine(label: DisplayText(verbatim: "Topped up"), balance: balance("18.50", currency: "USD")),
        ]

        XCTAssertEqual(visibleUsageLines(lines).map(\.label.resolved), ["Total balance", "Topped up"])
    }

    func testALineWithNothingToShowStaysHidden() {
        let lines = [
            UsageLine(label: DisplayText(verbatim: "Window without a percentage"), resetDate: Date()),
            UsageLine(label: DisplayText(verbatim: "Limit without usage"), total: 20, unit: "USD"),
        ]

        XCTAssertTrue(visibleUsageLines(lines).isEmpty)
    }

    private func balance(_ amount: String, currency: String) -> UsageBalance {
        UsageBalance(amount: .finite(Decimal(string: amount)!), unit: .currency(currency))
    }
}
