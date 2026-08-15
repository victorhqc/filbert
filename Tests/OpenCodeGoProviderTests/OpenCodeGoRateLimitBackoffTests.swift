import Foundation
@testable import OpenCodeGoProvider
import XCTest

final class OpenCodeGoRateLimitBackoffTests: XCTestCase {
    func testBackoff_doublesDelayAfterConsecutiveRateLimits() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1000))
        let backoff = OpenCodeGoRateLimitBackoff(
            baseDelay: 10,
            maximumDelay: 60,
            now: { clock.now }
        )

        await backoff.recordRateLimit()
        await assertThrowsRateLimited { try await backoff.checkRequestAllowed() }

        clock.advance(by: 10)
        try await backoff.checkRequestAllowed()
        await backoff.recordRateLimit()

        clock.advance(by: 19)
        await assertThrowsRateLimited { try await backoff.checkRequestAllowed() }

        clock.advance(by: 1)
        try await backoff.checkRequestAllowed()
    }

    private func assertThrowsRateLimited(operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected rateLimited")
        } catch let error as OpenCodeGoError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value.addTimeInterval(interval)
        lock.unlock()
    }
}
