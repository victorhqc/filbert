@testable import App
import Core
import XCTest

final class MonthlyBudgetPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 60 * 60

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

    func testAFreshThirtyOneDayMonthShowsADailyAllowance() throws {
        let remainingTime = 30 * day + 14 * 60 * 60
        let pace = try XCTUnwrap(pace(days: 31, usedPercentage: 3.3, remainingTime: remainingTime))

        XCTAssertEqual(pace.elapsedFraction, 1 - remainingTime / (31 * day), accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(perDay(pace)), 96.7 / (remainingTime / day), accuracy: 0.000_001)
        let text = PacedUsageLineText(pace: pace, forecast: nil)
        XCTAssertEqual(text.allowance, "About 3.2%/day available")
        XCTAssertEqual(text.accessibilitySentences.last, "About 3.2%/day available")
        XCTAssertEqual(pace.tier, .good)
    }

    func testATwentyEightDayMonthPacesFromStartToEnd() throws {
        let start = try XCTUnwrap(pace(days: 28, usedPercentage: 2, remainingTime: 27.5 * day))
        let middle = try XCTUnwrap(pace(days: 28, usedPercentage: 40, remainingTime: 14 * day))
        let end = try XCTUnwrap(pace(days: 28, usedPercentage: 90, remainingTime: 12 * 60 * 60))

        XCTAssertEqual(start.elapsedFraction, 0.5 / 28, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(perDay(start)), 98 / 27.5, accuracy: 0.000_001)
        XCTAssertEqual(middle.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(perDay(middle)), 60.0 / 14, accuracy: 0.000_001)
        XCTAssertEqual(end.elapsedFraction, 1 - 0.5 / 28, accuracy: 0.000_001)
        XCTAssertEqual(end.allowance, .untilReset(percentage: 10))
        XCTAssertEqual(end.warningBoundary, 100)
    }

    func testAThirtyOneDayMonthPacesFromStartToEnd() throws {
        let start = try XCTUnwrap(pace(days: 31, usedPercentage: 2, remainingTime: 30.5 * day))
        let middle = try XCTUnwrap(pace(days: 31, usedPercentage: 40, remainingTime: 15.5 * day))
        let end = try XCTUnwrap(pace(days: 31, usedPercentage: 90, remainingTime: day))

        XCTAssertEqual(start.elapsedFraction, 0.5 / 31, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(perDay(start)), 98 / 30.5, accuracy: 0.000_001)
        XCTAssertEqual(middle.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(perDay(middle)), 60 / 15.5, accuracy: 0.000_001)
        XCTAssertEqual(end.elapsedFraction, 30.0 / 31, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(perDay(end)), 10, accuracy: 0.000_001)
    }

    func testTheAllowanceSwitchesToUntilResetBelow24Hours() throws {
        let lastDay = try XCTUnwrap(pace(days: 31, usedPercentage: 40, remainingTime: day))
        let lastHours = try XCTUnwrap(pace(days: 31, usedPercentage: 40, remainingTime: day - 60))

        XCTAssertEqual(lastDay.allowance, .perDay(percentage: 60))
        XCTAssertEqual(lastHours.allowance, .untilReset(percentage: 60))
        XCTAssertEqual(PacedUsageLineText(pace: lastHours, forecast: nil).allowance, "60% available until reset")
    }

    func testTheTierUsesTheDailyAllowanceWithOnePointOfTolerance() throws {
        let withinTolerance = try XCTUnwrap(pace(days: 31, usedPercentage: 53.9, remainingTime: 15.5 * day))
        let aboveTolerance = try XCTUnwrap(pace(days: 31, usedPercentage: 54.1, remainingTime: 15.5 * day))
        let exhausted = try XCTUnwrap(pace(days: 31, usedPercentage: 100, remainingTime: 15.5 * day))

        XCTAssertEqual(withinTolerance.warningBoundary, 50 + 46.1 / 15.5, accuracy: 0.000_001)
        XCTAssertEqual(withinTolerance.tier, .good)
        XCTAssertEqual(aboveTolerance.warningBoundary, 50 + 45.9 / 15.5, accuracy: 0.000_001)
        XCTAssertEqual(aboveTolerance.tier, .warn)
        XCTAssertEqual(exhausted.tier, .critical)
    }

    func testDividersMarkTheWeeksOfTheRealMonth() throws {
        let fractions = { (days: Double) in
            try XCTUnwrap(BudgetPace.configuration(for: days * self.day)).dividerFractions
        }

        XCTAssertEqual(try fractions(28), [7.0 / 28, 14.0 / 28, 21.0 / 28])
        XCTAssertEqual(try fractions(31), [7.0 / 31, 14.0 / 31, 21.0 / 31, 28.0 / 31])
        XCTAssertEqual(try fractions(7), (1 ... 6).map { Double($0) / 7 })
    }

    func testAThirtyDayLineIsACalendarMonth() throws {
        let pace = try XCTUnwrap(BudgetPace(
            line: line(duration: UsageWindowDuration.month, usedPercentage: 30, remainingTime: 26 * day),
            now: now
        ))

        XCTAssertEqual(try XCTUnwrap(perDay(pace)), 70.0 / 26, accuracy: 0.000_001)
    }

    func testMonthlyPaceIsAvailableToAnyProviderSupplyingACalendarMonth() throws {
        let line = line(duration: 31 * day, usedPercentage: 30, remainingTime: 20 * day)
        let quota = ProviderQuota(
            providerId: "some-future-provider",
            providerName: "Future Provider",
            headline: DisplayText(verbatim: "30%"),
            lines: [line],
            lastUpdated: now
        )

        XCTAssertEqual(try XCTUnwrap(BudgetPace(line: line, now: now)).tier, .good)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .good)
    }

    func testMonthlyClampsOutOfRangePercentages() throws {
        let negative = try XCTUnwrap(pace(days: 30, usedPercentage: -10, remainingTime: 26 * day))
        let over = try XCTUnwrap(pace(days: 30, usedPercentage: 250, remainingTime: 12 * day))

        XCTAssertEqual(negative.usedPercentage, 0)
        XCTAssertEqual(negative.remainingPercentage, 100)
        XCTAssertEqual(over.usedPercentage, 100)
        XCTAssertEqual(over.remainingPercentage, 0)
        XCTAssertEqual(over.tier, .critical)
    }

    func testRejectsDurationsOutsideCalendarMonths() {
        for duration in [27 * day, 32 * day, UsageWindowDuration.fiveHours, 0, -7 * day] {
            XCTAssertNil(BudgetPace.configuration(for: duration), "\(duration)")
            XCTAssertNil(BudgetPace(line: line(duration: duration, usedPercentage: 30, remainingTime: day), now: now))
        }
    }

    func testRejectsMonthlyLinesWithMissingOrNonFiniteData() {
        XCTAssertNil(BudgetPace(
            line: UsageLine(label: DisplayText(verbatim: "Monthly"), percentage: 30, windowDuration: 31 * day),
            now: now
        ))
        XCTAssertNil(BudgetPace(line: line(duration: 31 * day, usedPercentage: .nan, remainingTime: day), now: now))
        XCTAssertNil(BudgetPace(
            line: line(duration: 31 * day, usedPercentage: .infinity, remainingTime: day),
            now: now
        ))
    }

    func testRejectsResetsOutsideTheLinesOwnDuration() {
        XCTAssertNil(pace(days: 31, usedPercentage: 30, remainingTime: 0))
        XCTAssertNil(pace(days: 31, usedPercentage: 30, remainingTime: -60 * 60))
        XCTAssertNil(pace(days: 28, usedPercentage: 30, remainingTime: 28 * day + 1))
        XCTAssertNotNil(pace(days: 31, usedPercentage: 30, remainingTime: 31 * day))
    }

    private func pace(days: Double, usedPercentage: Double, remainingTime: TimeInterval) -> BudgetPace? {
        BudgetPace(
            line: line(duration: days * day, usedPercentage: usedPercentage, remainingTime: remainingTime),
            now: now
        )
    }

    private func perDay(_ pace: BudgetPace) -> Double? {
        guard case let .perDay(percentage) = pace.allowance else { return nil }
        return percentage
    }

    private func line(duration: TimeInterval, usedPercentage: Double, remainingTime: TimeInterval) -> UsageLine {
        UsageLine(
            label: DisplayText(verbatim: "Monthly"),
            percentage: usedPercentage,
            resetDate: now.addingTimeInterval(remainingTime),
            windowDuration: duration
        )
    }
}
