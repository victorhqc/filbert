@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterCadenceTests: AllowanceForecasterTestCase {
    func testExtraObservationsWithoutANewValueProduceTheSameForecast() throws {
        let sparse: [(minute: Double, consumed: Decimal)] = [(0, 0), (10, 0), (20, 4), (32, 4), (42, 8), (52, 8)]
        let flatExtras: [(minute: Double, consumed: Decimal)] = (1 ... 9).map { (Double($0), 0) }
            + (21 ... 31).map { (Double($0), 4) }
            + (43 ... 51).map { (Double($0), 8) }
        let manualRefreshes: [(minute: Double, consumed: Decimal)] = (1 ... 9).map { (45 + Double($0) / 10, 8) }
        let dense = (sparse + flatExtras + manualRefreshes).sorted { $0.minute < $1.minute }

        recordTrace(sparse, providerId: "sparse")
        recordTrace(dense, providerId: "dense")

        let sparseForecast = try XCTUnwrap(forecast(at: minute(52), providerId: "sparse"))
        XCTAssertEqual(forecast(at: minute(52), providerId: "dense"), sparseForecast)
        XCTAssertEqual(sparseForecast.evidenceSpan, 30 * 60)
        try assertRemainingUse(at: minute(52), providerId: "sparse", equalsMinutes: 690)
    }

    func testBurstAtTheEndOfTheWindowSpreadsOverTheWholeWindow() throws {
        recordTrace([(0, 0), (5, 1), (10, 2), (15, 3), (20, 4), (25, 5), (30, 15)])

        try assertRemainingUse(at: minute(30), equalsMinutes: 85 / 0.5)
    }

    func testBurstAtTheStartOfTheWindowStopsCountingOnceItLeaves() throws {
        recordTrace([(0, 0), (5, 10), (10, 11), (15, 12), (20, 13), (25, 14), (30, 15)])
        try assertRemainingUse(at: minute(30), equalsMinutes: 85 / 0.5)

        recordTrace([(35, 16)])
        try assertRemainingUse(at: minute(35), equalsMinutes: 84 / 0.2)
    }

    func testTenSecondIntervalKeepsTwoHoursOfEvidence() {
        let finalStep = 720
        for step in 0 ... finalStep {
            let consumed: Decimal = switch step {
            case 0: 0
            case finalStep: 2
            default: 1
            }
            record(fixedPeriodMetric(consumed: consumed, at: origin.addingTimeInterval(Double(step) * 10)))
        }

        let forecast = forecast(at: minute(120))
        XCTAssertEqual(forecast?.evidenceSpan, 2 * 60 * 60)
        XCTAssertNotNil(depletion(at: minute(120)))
    }

    func testSlowIntervalsWithinTheMaximumGapProduceAnEstimate() {
        let fetchTime: TimeInterval = 5
        for interval: TimeInterval in [15 * 60, 29 * 60 + fetchTime] {
            let providerId = "every-\(Int(interval))s"
            for step in 0 ... 3 {
                record(
                    fixedPeriodMetric(consumed: Decimal(step), at: origin.addingTimeInterval(Double(step) * interval)),
                    providerId: providerId
                )
            }

            let latest = origin.addingTimeInterval(3 * interval)
            guard case .estimated = forecast(at: latest, providerId: providerId)?.state else {
                return XCTFail("Expected an estimate at a \(interval)-second interval")
            }
        }
    }

    func testThirtyOneMinuteIntervalShowsUpdatesTooFarApart() {
        recordTrace([(0, 0), (31, 1), (62, 2), (93, 3)])

        XCTAssertEqual(state(at: minute(93)), .tooFarApart)
    }
}

private extension AllowanceForecasterCadenceTests {
    func assertRemainingUse(
        at time: Date,
        providerId: String? = nil,
        equalsMinutes expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let forecast = try XCTUnwrap(forecast(at: time, providerId: providerId), file: file, line: line)
        let remaining = try XCTUnwrap(forecast.remainingUse(at: time), file: file, line: line)
        XCTAssertEqual(remaining, expected * 60, accuracy: 0.001, file: file, line: line)
    }
}
