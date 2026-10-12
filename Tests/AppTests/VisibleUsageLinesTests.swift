@testable import App
import Core
import XCTest

final class VisibleUsageLinesTests: XCTestCase {
    func testTheCardShowsEveryLineWithSomethingToShow() {
        let lines = [
            UsageLine(label: "Window", percentage: 30),
            UsageLine(label: "Empty credits", balance: UsageBalance(amount: .finite(0), unit: .credits)),
            UsageLine(label: "Unlimited credits", balance: UsageBalance(amount: .unlimited, unit: .credits)),
            UsageLine(label: "Bonus credits", used: 20, unit: "USD"),
            UsageLine(label: "Credits", details: [UsageDetail(label: "Credits", value: "12.5")]),
        ]

        XCTAssertEqual(visibleUsageLines(lines).map(\.label), lines.map(\.label))
    }

    func testEqualAmountsAreNoLongerMerged() {
        let lines = [
            UsageLine(label: "Total balance", balance: balance("18.50", currency: "USD")),
            UsageLine(label: "Topped up", balance: balance("18.50", currency: "USD")),
        ]

        XCTAssertEqual(visibleUsageLines(lines).map(\.label), ["Total balance", "Topped up"])
    }

    func testALineWithNothingToShowStaysHidden() {
        let lines = [
            UsageLine(label: "Window without a percentage", resetDate: Date()),
            UsageLine(label: "Limit without usage", total: 20, unit: "USD"),
        ]

        XCTAssertTrue(visibleUsageLines(lines).isEmpty)
    }

    private func balance(_ amount: String, currency: String) -> UsageBalance {
        UsageBalance(amount: .finite(Decimal(string: amount)!), unit: .currency(currency))
    }
}
