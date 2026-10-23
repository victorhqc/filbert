import Core
@testable import KimiCodeProvider
import XCTest

final class KimiCodeDecodingTests: KimiCodeProviderTestCase {
    // MARK: - Values

    func testNumbersAndNumericStringsBothDecode() async throws {
        let quota = try await fetch(json: """
        {"usage":{"limit":100,"used":30},
         "limits":[{"window":{"duration":"300","timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"50"}}],
         "usages":{"limit_month_total":{"used_ratio":"0.25"}}}
        """)

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage", "weekly-usage", "monthly-usage"])
        assertPercentages(quota, [25, 30, 25])
    }

    func testEveryResetKeySpellingDecodes() async throws {
        for key in ["resetTime", "resetAt", "reset_time", "reset_at"] {
            let quota = try await fetch(json: """
            {"usages":{"limit_month_total":{"used_ratio":0.1,"\(key)":"2099-01-01T00:00:00Z"}}}
            """)

            XCTAssertEqual(quota.lines.first?.resetDate, try date("2099-01-01T00:00:00Z"), key)
        }
    }

    func testMissingUsedIsLimitMinusRemaining() async throws {
        let quota = try await fetch(json: #"{"usage":{"limit":"100","remaining":"35"}}"#)

        assertPercentages(quota, [65])
    }

    func testPercentagesAreClamped() async throws {
        let quota = try await fetch(json: """
        {"usage":{"limit":"100","remaining":"130"},
         "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","used":"120"}}],
         "usages":{"limit_month_total":{"used_ratio":-0.5}}}
        """)

        assertPercentages(quota, [100, 0, 0])
    }

    func testRatioAboveOneIsClamped() async throws {
        let quota = try await fetch(json: #"{"usages":{"limit_month_total":{"used_ratio":1.05}}}"#)

        assertPercentages(quota, [100])
    }

    // MARK: - Dropped entries

    func testMalformedEntriesAreDroppedWithoutFailing() async throws {
        let quota = try await fetch(json: """
        {"usage":{"limit":"0","used":"0","remaining":"0"},
         "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100"}}],
         "usages":{"limit_5h":"half",
                   "limit_7d":{"reset_time":"2099-01-01T00:00:00Z"},
                   "limit_month_total":{"used_ratio":"abc"}}}
        """)

        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertEqual(quota.headline.resolved, "No data")
    }

    func testAMalformedBlockLeavesTheOthers() async throws {
        let quota = try await fetch(json: """
        {"usage":"weekly","limits":{"window":"5h"},"usages":{"limit_5h":{"used_ratio":0.1}}}
        """)

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage"])
        assertPercentages(quota, [10])
    }

    func testMonthlyCodeShareAndUnknownKeysAreIgnored() async throws {
        let quota = try await fetch(json: """
        {"goods_version":2,
         "usages":{"limit_month_code":{"used_ratio":0.9},"limit_week":{"used_ratio":0.3}},
         "booster_wallet":{"balance":{"type":"BOOSTER","amount":"1","amountLeft":"1"}}}
        """)

        XCTAssertTrue(quota.lines.isEmpty)
    }

    func testEmptyObjectReadsNoData() async throws {
        let quota = try await fetch(json: "{}")

        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertEqual(quota.headline.resolved, "No data")
    }

    // MARK: - Windows

    func testFiveHoursInHoursIsTheFiveHourWindow() async throws {
        let quota = try await fetch(json: """
        {"limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":"100","used":"40"}}]}
        """)

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage"])
        assertPercentages(quota, [40])
    }

    func testOtherLegacyWindowsAreIgnored() async throws {
        let quota = try await fetch(json: """
        {"limits":[{"window":{"duration":60,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","used":"40"}},
                   {"window":{"duration":1,"timeUnit":"TIME_UNIT_FORTNIGHT"},"detail":{"limit":"100","used":"40"}}]}
        """)

        XCTAssertTrue(quota.lines.isEmpty)
    }

    // MARK: - Merge

    func testHigherRatioWinsWithItsOwnReset() async throws {
        let quota = try await fetch(json: """
        {"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
                    "detail":{"limit":"100","used":"10","resetTime":"2099-01-01T00:00:00Z"}}],
         "usages":{"limit_5h":{"used_ratio":0.6,"reset_time":"2099-01-02T00:00:00Z"}}}
        """)

        assertPercentages(quota, [60])
        XCTAssertEqual(quota.lines.first?.resetDate, try date("2099-01-02T00:00:00Z"))
    }

    func testWinnerWithoutAResetBorrowsTheOther() async throws {
        let quota = try await fetch(json: """
        {"usage":{"limit":"100","used":"90"},
         "usages":{"limit_7d":{"used_ratio":0.1,"reset_time":"2099-01-02T00:00:00Z"}}}
        """)

        assertPercentages(quota, [90])
        XCTAssertEqual(quota.lines.first?.resetDate, try date("2099-01-02T00:00:00Z"))
    }
}
