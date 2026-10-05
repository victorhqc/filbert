import Core
import Foundation
import XCTest

final class ProviderRetryGateTests: XCTestCase {
    func testRemainingIsZeroWithoutADeadline() {
        let gate = ProviderRetryGate(now: { 0 })

        XCTAssertEqual(gate.remaining, 0)
    }

    func testRecordStartsADeadlineThatDecaysWithTheClock() {
        let clock = GateClock()
        let gate = ProviderRetryGate(now: { clock.elapsed() })

        gate.record(retryAfter: 120)

        XCTAssertEqual(gate.remaining, 120)
        clock.advance(by: 30)
        XCTAssertEqual(gate.remaining, 90)
        clock.advance(by: 90)
        XCTAssertEqual(gate.remaining, 0)
    }

    func testRecordKeepsTheLaterDeadline() {
        let clock = GateClock()
        let gate = ProviderRetryGate(now: { clock.elapsed() })

        gate.record(retryAfter: 300)
        gate.record(retryAfter: 60)

        XCTAssertEqual(gate.remaining, 300)
    }

    func testRecordExtendsWithALaterDeadline() {
        let clock = GateClock()
        let gate = ProviderRetryGate(now: { clock.elapsed() })

        gate.record(retryAfter: 60)
        clock.advance(by: 30)
        gate.record(retryAfter: 120)

        XCTAssertEqual(gate.remaining, 120)
    }

    func testRecordIgnoresNonPositiveDelays() {
        let gate = ProviderRetryGate(now: { 0 })

        gate.record(retryAfter: 0)
        gate.record(retryAfter: -5)
        gate.record(retryAfter: .infinity)

        XCTAssertEqual(gate.remaining, 0)
    }

    func testClearOpensTheGate() {
        let gate = ProviderRetryGate(now: { 0 })

        gate.record(retryAfter: 120)
        gate.clear()

        XCTAssertEqual(gate.remaining, 0)
    }
}

private final class GateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0

    func elapsed() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        value += interval
    }
}
