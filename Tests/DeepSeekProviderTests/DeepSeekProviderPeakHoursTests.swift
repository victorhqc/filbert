import Core
@testable import DeepSeekProvider
import XCTest

final class DeepSeekProviderPeakHoursTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testFetchQuota_includesAnnouncedPeakHoursSchedule() async throws {
        let quota = try await fetchQuota()
        let config = try XCTUnwrap(quota.peakHoursConfig)

        XCTAssertEqual(config.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(config.windows, [
            PeakHoursWindow(startHour: 1, endHour: 4),
            PeakHoursWindow(startHour: 6, endHour: 10),
        ])
        XCTAssertEqual(config.peakMultiplier, 2)
        XCTAssertEqual(config.offPeakMultiplier, 1)
        XCTAssertEqual(config.effectiveDate, Date(timeIntervalSince1970: 1_786_896_000))
    }

    func testPeakHoursSchedule_observesActivationAndWindowBoundaries() throws {
        let config = DeepSeekProvider.peakHoursConfig
        let effectiveDate = try XCTUnwrap(config.effectiveDate)

        XCTAssertFalse(config.isScheduleActive(at: effectiveDate.addingTimeInterval(-1)))
        XCTAssertNil(config.multiplier(at: effectiveDate.addingTimeInterval(-1)))
        XCTAssertTrue(config.isScheduleActive(at: effectiveDate))

        XCTAssertEqual(config.multiplier(at: utcDate(hour: 1)), 2)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 3, minute: 59)), 2)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 4)), 1)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 5, minute: 59)), 1)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 6)), 2)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 9, minute: 59)), 2)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 10)), 1)
    }

    private func fetchQuota() async throws -> ProviderQuota {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = DeepSeekProvider(session: URLSession(configuration: configuration))
        MockURLProtocol.responseData = Data("""
        {
          "is_available": true,
          "balance_infos": []
        }
        """.utf8)
        return try await provider.fetchQuota(
            auth: .apiKey("test-key"),
            baseURL: DeepSeekProvider.baseURL
        )
    }

    private func utcDate(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
