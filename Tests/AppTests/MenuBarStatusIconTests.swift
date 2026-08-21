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
            headline: "42%",
            lines: [
                UsageLine(label: "5-hour window", percentage: 42),
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
            headline: "42%",
            lines: [
                UsageLine(label: "5-hour window", percentage: 42),
                UsageLine(label: "Weekly", percentage: 37),
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
            headline: "",
            lines: [
                UsageLine(label: "Monthly", used: 25, total: 100),
            ],
            lastUpdated: Date()
        )

        let status = QuotaStatusResolver.resolve(for: quota)
        XCTAssertEqual(status, .window(percentage: 25))
    }

    // MARK: - balance-based provider → balance mode

    func testResolve_noPercentageButPositiveTotal_returnsBalanceMode() {
        let quota = ProviderQuota(
            providerId: "deepseek",
            providerName: "DeepSeek",
            headline: "$12.34",
            lines: [
                UsageLine(label: "Total balance", total: 12.34, unit: "USD"),
            ],
            lastUpdated: Date()
        )

        let status = QuotaStatusResolver.resolve(for: quota)
        guard case let .balance(used, total, amount) = status else {
            return XCTFail("Expected .balance, got \(status)")
        }
        XCTAssertNil(used)
        XCTAssertEqual(total, 12.34, accuracy: 0.001)
        XCTAssertFalse(amount.isEmpty, "amount text must be formatted")
    }

    func testResolve_multipleBalanceLines_picksFirstPositiveTotal() {
        let quota = ProviderQuota(
            providerId: "deepseek",
            providerName: "DeepSeek",
            headline: "",
            lines: [
                UsageLine(label: "Total balance", total: 12.34, unit: "USD"),
                UsageLine(label: "Gift balance", total: 1.00, unit: "USD"),
            ],
            lastUpdated: Date()
        )

        let status = QuotaStatusResolver.resolve(for: quota)
        guard case let .balance(_, total, _) = status else {
            return XCTFail("Expected .balance, got \(status)")
        }
        XCTAssertEqual(total, 12.34, accuracy: 0.001)
    }

    // MARK: - fallback when no usable data

    func testResolve_noLines_returnsFallback() {
        let quota = ProviderQuota(
            providerId: "zai",
            providerName: "Z.AI",
            headline: "",
            lines: [],
            lastUpdated: Date()
        )

        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota), .fallback)
    }

    func testResolve_zeroTotalBalance_returnsFallback() {
        let quota = ProviderQuota(
            providerId: "deepseek",
            providerName: "DeepSeek",
            headline: "",
            lines: [
                UsageLine(label: "Total balance", used: 0, total: 0, unit: "USD"),
            ],
            lastUpdated: Date()
        )

        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota), .fallback)
    }

    func testResolve_percentageWinsOverBalance_whenBothPresent() {
        let quota = ProviderQuota(
            providerId: "capped",
            providerName: "Capped",
            headline: "",
            lines: [
                UsageLine(label: "Window", percentage: 30),
                UsageLine(label: "Balance", total: 100, unit: "USD"),
            ],
            lastUpdated: Date()
        )

        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota), .window(percentage: 30))
    }

    // MARK: - balance ring fraction

    func testResolve_balanceWithNilUsed_drivesFullRingAtRender() {
        let quota = ProviderQuota(
            providerId: "deepseek",
            providerName: "DeepSeek",
            headline: "",
            lines: [
                UsageLine(label: "Total balance", used: nil, total: 12.34, unit: "USD"),
            ],
            lastUpdated: Date()
        )

        guard case let .balance(used, total, _) = QuotaStatusResolver.resolve(for: quota) else {
            return XCTFail("Expected .balance")
        }
        XCTAssertNil(used)
        XCTAssertEqual(total, 12.34, accuracy: 0.001)
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
            headline: "",
            lines: [UsageLine(label: "Window", percentage: 150)],
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
            QuotaStatusResolver.tier(for: .balance(used: nil, total: 4.99, formattedAmount: "$4.99")),
            .critical
        )
        XCTAssertEqual(
            QuotaStatusResolver.tier(for: .balance(used: nil, total: 5, formattedAmount: "$5.00")),
            .warn
        )
        XCTAssertEqual(
            QuotaStatusResolver.tier(for: .balance(used: 500, total: 20, formattedAmount: "$20.00")),
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
