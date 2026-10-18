@testable import App
import AppKit
import Core
import XCTest

// MARK: - MenuBarStatusIcon resolution logic

final class MenuBarStatusIconTests: XCTestCase {
    private let suiteName = "filbert.tests.menu-bar-status-icon"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        BalanceThresholds.setUserDefaults(defaults)
        BalanceThresholds.set(low: 5, ok: 20)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        BalanceThresholds.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testStatusVisualKeepsThePercentageRingWhenVintageMacIsDisabled() {
        XCTAssertEqual(
            MenuBarStatusVisual.statusImage(
                for: .window(percentage: 84),
                isVintageMacEnabled: false
            ),
            .ring(bucket: 0.8)
        )
    }

    func testStatusVisualUsesVintageMacFaceForAnAutomaticProviderStatus() {
        XCTAssertEqual(
            MenuBarStatusVisual.statusImage(
                for: .window(percentage: 84),
                isVintageMacEnabled: true
            ),
            .macFace(tier: .critical)
        )
    }

    // MARK: - window-based provider → percentage mode

    func testResolve_windowPercentage_returnsWindowMode() {
        let quota = ProviderQuota(
            providerId: "claude-code",
            providerName: "Claude Code",
            headline: DisplayText(verbatim: "42%"),
            lines: [
                UsageLine(label: DisplayText(verbatim: "5-hour window"), percentage: 42),
            ],
            lastUpdated: Date()
        )

        let status = QuotaStatusResolver.resolve(for: quota)
        XCTAssertEqual(status, .window(percentage: 42))
    }

    func testResolve_5HourBeforeWeekly_picks5HourFirst() {
        let quota = ProviderQuota(
            providerId: "claude-code",
            providerName: "Claude Code",
            headline: DisplayText(verbatim: "42%"),
            lines: [
                UsageLine(label: DisplayText(verbatim: "5-hour window"), percentage: 42),
                UsageLine(label: DisplayText(verbatim: "Weekly"), percentage: 37),
            ],
            lastUpdated: Date()
        )

        let status = QuotaStatusResolver.resolve(for: quota)
        XCTAssertEqual(status, .window(percentage: 42))
    }

    func testResolve_percentageDerivedFromUsedTotal_whenPercentageFieldMissing() {
        let quota = ProviderQuota(
            providerId: "zai",
            providerName: "Z.AI",
            headline: DisplayText(verbatim: ""),
            lines: [
                UsageLine(label: DisplayText(verbatim: "Monthly"), used: 25, total: 100),
            ],
            lastUpdated: Date()
        )

        let status = QuotaStatusResolver.resolve(for: quota)
        XCTAssertEqual(status, .window(percentage: 25))
    }

    // MARK: - balance-based provider → balance mode

    func testResolve_currencyBalance_returnsBalanceMode() {
        let status = QuotaStatusResolver.resolve(for: quota([
            UsageLine(label: DisplayText(verbatim: "Total balance"), balance: usdBalance("12.34")),
        ]))

        guard case let .balance(amount, formattedAmount) = status else {
            return XCTFail("Expected .balance, got \(status)")
        }
        XCTAssertEqual(amount, 12.34, accuracy: 0.001)
        XCTAssertTrue(formattedAmount.contains("12"), "amount text must be formatted: \(formattedAmount)")
    }

    func testResolve_multipleBalanceLines_picksFirstPositiveCurrencyBalance() {
        let status = QuotaStatusResolver.resolve(for: quota([
            UsageLine(label: DisplayText(verbatim: "Empty balance"), balance: usdBalance("0")),
            UsageLine(label: DisplayText(verbatim: "Total balance"), balance: usdBalance("12.34")),
            UsageLine(label: DisplayText(verbatim: "Gift balance"), balance: usdBalance("1.00")),
        ]))

        guard case let .balance(amount, _) = status else {
            return XCTFail("Expected .balance, got \(status)")
        }
        XCTAssertEqual(amount, 12.34, accuracy: 0.001)
    }

    func testResolve_creditsUnlimitedAndSpentAmounts_neverGiveAStatus() {
        let status = QuotaStatusResolver.resolve(for: quota([
            UsageLine(
                label: DisplayText(verbatim: "Credits"),
                balance: UsageBalance(amount: .finite(811.77), unit: .credits)
            ),
            UsageLine(
                label: DisplayText(verbatim: "Unlimited"),
                balance: UsageBalance(amount: .unlimited, unit: .currency("USD"))
            ),
            UsageLine(label: DisplayText(verbatim: "Bonus credits"), used: 20, unit: "USD"),
        ]))

        XCTAssertEqual(status, .fallback)
    }

    // MARK: - fallback when no usable data

    func testResolve_noLines_returnsFallback() {
        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota([])), .fallback)
    }

    func testResolve_zeroCurrencyBalance_returnsFallback() {
        let status = QuotaStatusResolver.resolve(for: quota([
            UsageLine(label: DisplayText(verbatim: "Total balance"), balance: usdBalance("0")),
        ]))

        XCTAssertEqual(status, .fallback)
    }

    func testResolve_percentageWinsOverBalance_whenBothPresent() {
        let status = QuotaStatusResolver.resolve(for: quota([
            UsageLine(label: DisplayText(verbatim: "Window"), percentage: 30),
            UsageLine(label: DisplayText(verbatim: "Balance"), balance: usdBalance("100")),
        ]))

        XCTAssertEqual(status, .window(percentage: 30))
    }

    // MARK: - headline dot

    func testFirstCurrencyBalance_skipsCreditsAndSpentAmounts() {
        let lines = [
            UsageLine(label: DisplayText(verbatim: "Window"), percentage: 30),
            UsageLine(
                label: DisplayText(verbatim: "Credits"),
                balance: UsageBalance(amount: .finite(811.77), unit: .credits)
            ),
            UsageLine(label: DisplayText(verbatim: "Bonus credits"), used: 20, unit: "USD"),
            UsageLine(label: DisplayText(verbatim: "Total balance"), balance: usdBalance("0")),
        ]

        XCTAssertEqual(QuotaStatusResolver.firstCurrencyBalance(in: lines), 0)
        XCTAssertNil(QuotaStatusResolver.firstCurrencyBalance(in: Array(lines.prefix(3))))
    }

    private func quota(_ lines: [UsageLine]) -> ProviderQuota {
        ProviderQuota(
            providerId: "test",
            providerName: "Test",
            headline: DisplayText(verbatim: ""),
            lines: lines,
            lastUpdated: Date()
        )
    }

    private func usdBalance(_ amount: String) -> UsageBalance {
        UsageBalance(amount: .finite(Decimal(string: amount)!), unit: .currency("USD"))
    }

    // MARK: - clamping

    func testClampedFraction_clampsNegativeToZero() {
        XCTAssertEqual(QuotaStatusResolver.clampedFraction(-5), 0)
    }

    func testClampedFraction_keepsInRange() {
        XCTAssertEqual(QuotaStatusResolver.clampedFraction(0.5), 0.5)
    }

    func testClampedFraction_clampsAboveOne() {
        XCTAssertEqual(QuotaStatusResolver.clampedFraction(1.5), 1)
        XCTAssertEqual(QuotaStatusResolver.clampedFraction(2), 1)
    }

    func testResolve_outOfRangePercentage_isPassedThroughAndClampedAtRender() {
        let quota = ProviderQuota(
            providerId: "buggy",
            providerName: "Buggy",
            headline: DisplayText(verbatim: ""),
            lines: [UsageLine(label: DisplayText(verbatim: "Window"), percentage: 150)],
            lastUpdated: Date()
        )

        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota), .window(percentage: 150))
        XCTAssertEqual(
            QuotaStatusResolver.clampedFraction(150 / 100),
            1,
            "the ring view clamps the resolved fraction to [0, 1] before drawing"
        )
    }

    func testTier_windowUsesPopoverThresholdBoundaries() {
        let cases: [(Double, QuotaStatusResolver.Tier)] = [
            (0, .good), (49, .good), (50, .warn), (79, .warn), (80, .critical), (100, .critical),
        ]

        for (percentage, expectedTier) in cases {
            XCTAssertEqual(
                QuotaStatusResolver.tier(for: .window(percentage: percentage)),
                expectedTier,
                "Unexpected tier for \(percentage)%"
            )
        }
    }

    func testTier_windowDoesNotClampTheResolvedPercentage() {
        XCTAssertEqual(QuotaStatusResolver.tier(for: .window(percentage: -1)), .good)
        XCTAssertEqual(QuotaStatusResolver.tier(for: .window(percentage: 101)), .critical)
    }

    func testTier_balanceUsesAvailableAmountAndConfiguredThresholds() {
        BalanceThresholds.set(low: 5, ok: 20)

        XCTAssertEqual(
            QuotaStatusResolver.tier(for: .balance(amount: 4.99, formattedAmount: "$4.99")),
            .critical
        )
        XCTAssertEqual(
            QuotaStatusResolver.tier(for: .balance(amount: 5, formattedAmount: "$5.00")),
            .warn
        )
        XCTAssertEqual(
            QuotaStatusResolver.tier(for: .balance(amount: 20, formattedAmount: "$20.00")),
            .good
        )
    }

    func testTier_fallbackReturnsNil() {
        XCTAssertNil(QuotaStatusResolver.tier(for: .fallback))
    }
}

// MARK: - Leading composite bitmap

final class MenuBarStatusCompositeTests: XCTestCase {
    func testCompositeSizePlacesTheIdentityColumnBeforeTheRing() {
        XCTAssertEqual(
            MenuBarStatusVisual.compositeSize(
                statusImage: .ring(bucket: 0.8),
                isFastRefreshActive: false
            ),
            CGSize(width: 30, height: 14)
        )
    }

    func testCompositeSizeKeepsTheIdentityCanvasWhenFast() {
        let notFast = MenuBarStatusVisual.compositeSize(
            statusImage: .ring(bucket: 0.8),
            isFastRefreshActive: false
        )
        let fast = MenuBarStatusVisual.compositeSize(
            statusImage: .ring(bucket: 0.8),
            isFastRefreshActive: true
        )

        XCTAssertEqual(fast.width, notFast.width)
        XCTAssertEqual(fast.height, 14)
    }

    func testCompositeSizeWithoutStatusVisualIsTheIdentityColumnAlone() {
        XCTAssertEqual(
            MenuBarStatusVisual.compositeSize(
                statusImage: nil,
                isFastRefreshActive: false
            ),
            CGSize(width: 14, height: 14)
        )
    }

    func testCompositeSizeAddsAnAwakeMarkWhenNoStatusVisualIsAvailable() {
        XCTAssertEqual(
            MenuBarStatusVisual.compositeSize(
                statusImage: nil,
                isFastRefreshActive: false,
                isSleepPreventionActive: true
            ),
            CGSize(width: 22, height: 14)
        )
    }

    func testCompositeSizeKeepsTheRingSizeWhenTheAwakeMarkIsOverlaid() {
        XCTAssertEqual(
            MenuBarStatusVisual.compositeSize(
                statusImage: .ring(bucket: 0.8),
                isFastRefreshActive: false,
                isSleepPreventionActive: true
            ),
            CGSize(width: 30, height: 14)
        )
    }

    func testCompositeImageIsAColoredBitmapAtTheCompositeSize() {
        let image = MenuBarStatusVisual.compositeImage(
            statusImage: .ring(bucket: 0.8),
            glyph: .sfSymbol("sparkles"),
            isFastRefreshActive: true
        )

        XCTAssertFalse(image.isTemplate)
        XCTAssertFalse(image.representations.isEmpty)
        XCTAssertEqual(image.size, CGSize(width: 30, height: 14))
    }
}
