@testable import App
import Core
import XCTest

final class FallbackPoolTrackerTests: FallbackPoolTestCase {
    private var tracker = FallbackPoolTracker()

    func testAPoolFallingOnTheReadThatReachesTheLimitIsPromoted() {
        record(fiveHour: 98, credits: "811.7749020000")
        record(fiveHour: 100, credits: "810.8374745000")

        XCTAssertEqual(tracker.promotedPoolIds(for: providerId), ["credits"])
    }

    func testAPoolFallingWhileTheGroupIsExhaustedIsPromoted() {
        record(fiveHour: 100, credits: "810.84")
        record(fiveHour: 100, credits: "808.31")

        XCTAssertEqual(tracker.promotedPoolIds(for: providerId), ["credits"])
    }

    func testTheFirstObservationAnUnchangedBalanceAndAnIncreaseNeverPromote() {
        record(fiveHour: 100, credits: "800")
        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)

        record(fiveHour: 100, credits: "800")
        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)

        record(fiveHour: 100, credits: "900")
        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    func testAFallingPoolIsNotPromotedWhileTheGroupHasRoomLeft() {
        record(fiveHour: 90, credits: "811")
        record(fiveHour: 95, credits: "810")

        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    func testAPoolWithoutADeclarationIsNeverPromoted() {
        record(fiveHour: 98, credits: "811", declaresFallback: false)
        record(fiveHour: 100, credits: "810", declaresFallback: false)

        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    func testStaleAndUnknownObservationsNeverCount() {
        record(fiveHour: 98, credits: "811")
        tracker.record(quota(fiveHour: 100, credits: decimal("810"), isStale: true), for: providerId)
        tracker.record(quota(fiveHour: 100, credits: decimal("809"), freshness: .unknown), for: providerId)

        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    func testAPromotedPoolStaysPromotedWhileTheGroupIsExhausted() {
        record(fiveHour: 98, credits: "811")
        record(fiveHour: 100, credits: "810")

        record(fiveHour: 100, credits: "810")
        XCTAssertEqual(tracker.promotedPoolIds(for: providerId), ["credits"])

        record(fiveHour: 100, credits: "900")
        XCTAssertEqual(tracker.promotedPoolIds(for: providerId), ["credits"])
    }

    func testThePoolStaysPromotedUntilNoLineOfTheGroupIsAtTheLimit() {
        record(fiveHour: 100, weekly: 100, credits: "811")
        record(fiveHour: 100, weekly: 100, credits: "810")

        record(fiveHour: 0, weekly: 100, credits: "809")
        XCTAssertEqual(tracker.promotedPoolIds(for: providerId), ["credits"])

        record(fiveHour: 2, weekly: 100, credits: "809")
        record(fiveHour: 3, weekly: 99, credits: "809")
        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    func testAFirstReadingAfterTheResetAboveZeroDemotes() {
        record(fiveHour: 98, credits: "811")
        record(fiveHour: 100, credits: "810")

        record(fiveHour: 4, credits: "810")

        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    func testResettingTheProviderStartsANewBaseline() {
        record(fiveHour: 98, credits: "811")
        record(fiveHour: 100, credits: "810")

        tracker.reset(for: providerId)
        record(fiveHour: 100, credits: "809")

        XCTAssertTrue(tracker.promotedPoolIds(for: providerId).isEmpty)
    }

    private func record(fiveHour: Double, weekly: Double = 66, credits: String, declaresFallback: Bool = true) {
        tracker.record(
            quota(fiveHour: fiveHour, weekly: weekly, credits: decimal(credits), declaresFallback: declaresFallback),
            for: providerId
        )
    }
}
