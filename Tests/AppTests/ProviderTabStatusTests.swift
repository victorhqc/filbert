@testable import App
import Core
import XCTest

final class ProviderTabStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testWindowFillsTheRingAndColorsThePercentage() {
        let quota = quota(lines: [UsageLine(label: DisplayText(verbatim: "Session"), percentage: 19)])

        let status = ProviderTabStatus.make(state: .loaded(quota), errorMessage: nil, at: now)

        XCTAssertEqual(status.ringFraction, 0.19, accuracy: 0.0001)
        XCTAssertEqual(status.tier, QuotaStatusResolver.compactTier(for: quota, at: now))
        XCTAssertEqual(status.value, .text(QuotaFormatting.percentage(19)))
        XCTAssertTrue(status.colorsValue)
    }

    func testWindowAboveTheLimitKeepsTheRingFull() {
        let quota = quota(lines: [UsageLine(label: DisplayText(verbatim: "Session"), percentage: 130)])

        let status = ProviderTabStatus.make(state: .loaded(quota), errorMessage: nil, at: now)

        XCTAssertEqual(status.ringFraction, 1)
    }

    func testBalanceShowsAFullTierRingAndANeutralAmount() throws {
        let amount = try XCTUnwrap(Decimal(string: "23.64"))
        let quota = quota(lines: [
            UsageLine(
                label: DisplayText(verbatim: "Balance"),
                balance: UsageBalance(amount: .finite(amount), unit: .currency("USD"))
            ),
        ])
        guard case let .balance(_, formattedAmount) = QuotaStatusResolver.resolve(for: quota) else {
            return XCTFail("Expected a balance status")
        }

        let status = ProviderTabStatus.make(state: .loaded(quota), errorMessage: nil, at: now)

        XCTAssertEqual(status.ringFraction, 1)
        XCTAssertEqual(status.tier, .good)
        XCTAssertEqual(status.value, .text(formattedAmount))
        XCTAssertFalse(status.colorsValue)
    }

    func testCreditsShowTheAmountOnAnEmptyTrack() throws {
        let amount = try XCTUnwrap(Decimal(string: "803.74"))
        let quota = quota(lines: [
            UsageLine(
                label: DisplayText(verbatim: "5-hour window"),
                percentage: 100,
                id: "five-hour",
                limitGroup: "subscription"
            ),
            UsageLine(
                label: DisplayText(verbatim: "Credits"),
                balance: UsageBalance(amount: .finite(amount), unit: .credits),
                id: "credits",
                fallbackForLimitGroup: "subscription"
            ),
        ])
        guard case let .credits(formattedAmount) = QuotaStatusResolver.resolve(for: quota) else {
            return XCTFail("Expected the credits pool to be promoted")
        }

        let status = ProviderTabStatus.make(state: .loaded(quota), errorMessage: nil, at: now)

        XCTAssertEqual(status.ringFraction, 0)
        XCTAssertNil(status.tier)
        XCTAssertEqual(status.value, .text(formattedAmount))
    }

    func testFallbackShowsAnEmptyTrackAndNoValue() {
        let quota = quota(lines: [])

        let status = ProviderTabStatus.make(state: .loaded(quota), errorMessage: nil, at: now)

        XCTAssertEqual(status, .emptyTrack)
    }

    func testSetupShowsAnEmptyTrackAndNoValue() {
        let status = ProviderTabStatus.make(
            state: .setup(DisplayText(verbatim: "Add a key")),
            errorMessage: nil,
            at: now
        )

        XCTAssertEqual(status, .emptyTrack)
    }

    func testLoadingShowsProgressInPlaceOfTheValue() {
        let status = ProviderTabStatus.make(state: .loading, errorMessage: nil, at: now)

        XCTAssertEqual(status.value, .progress)
        XCTAssertEqual(status.ringFraction, 0)
    }

    func testErrorStateShowsTheWarning() {
        let status = ProviderTabStatus.make(
            state: .error(DisplayText(verbatim: "Authentication failed")),
            errorMessage: "Authentication failed",
            at: now
        )

        XCTAssertEqual(status.value, .warning("Authentication failed"))
        XCTAssertEqual(status.ringFraction, 0)
    }

    func testRefreshErrorKeepsTheRingAndShowsTheWarning() {
        let quota = quota(lines: [UsageLine(label: DisplayText(verbatim: "Session"), percentage: 40)])

        let status = ProviderTabStatus.make(state: .loaded(quota), errorMessage: "Offline", at: now)

        XCTAssertEqual(status.ringFraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(status.value, .warning("Offline"))
        XCTAssertFalse(status.colorsValue)
    }

    private func quota(lines: [UsageLine]) -> ProviderQuota {
        ProviderQuota(
            providerId: "tab-test",
            providerName: "Tab Test",
            headline: DisplayText(verbatim: ""),
            lines: lines,
            lastUpdated: now
        )
    }
}
