@testable import App
import Core
import XCTest

// MARK: - MenuBarStatusIcon resolution logic (ui 10)

/// Exercises the pure `QuotaStatusResolver` that drives the menu-bar icon's
/// branch selection (ui 10 Plan §6). The ring geometry itself is verified via
/// `QuotaStatusResolver.clampedFraction` — the same function the view calls.
final class MenuBarStatusIconTests: XCTestCase {
    // MARK: - AC3: window-based provider → percentage mode

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
        // Mirrors the Claude Code provider's line ordering (providers 02 AC5):
        // 5-hour window first, then weekly. The icon picks the first one with a
        // non-nil percentage so it agrees with the popover's headline priority
        // (ui 04 AC2, providers 01 AC5).
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

    // MARK: - AC4: balance-based provider → balance mode

    func testResolve_noPercentageButPositiveTotal_returnsBalanceMode() {
        // DeepSeek emits balance lines with `used: nil` (providers 04) so the
        // percentage derivation returns nil and the line is treated as a
        // balance-only line (ui 08 AC3).
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
        // Mirrors `headlineBalanceColor(for:)`'s selection rule (ui 08 AC3):
        // the first balance-only line with a positive total drives the ring.
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

    // MARK: - AC5: fallback when no usable data

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
        // Capped API plans can return both (per core 01). The icon picks the
        // percentage line (ui 10 AC3) so it agrees with the popover's headline.
        // The balance line keeps `used: nil` to stay a real balance line.
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

    // MARK: - AC4: balance ring fraction

    func testResolve_balanceWithNilUsed_drivesFullRingAtRender() {
        // Real balance providers emit `used: nil` (providers 04). AC4: a full
        // ring is drawn when `used` is nil but `total > 0`. The resolver hands
        // the used value through; the ring view decides to draw a full circle.
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

    // MARK: - AC6: clamping

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
        // The resolver does not clamp the percentage itself — the ring view
        // clamps at draw time (ui 10 AC6). Verify the resolver hands the raw
        // value through and the clamp helper handles the edge.
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
}
