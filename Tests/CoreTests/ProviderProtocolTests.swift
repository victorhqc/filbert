import Core
import XCTest

final class ProviderProtocolTests: XCTestCase {
    func testProviderQuota_initializesAllFields() {
        let now = Date()
        let detail = UsageDetail(label: "RPM", value: "42 / 500")
        let line = UsageLine(
            label: "5-hour window",
            used: 420,
            total: 1000,
            percentage: 42,
            unit: "requests",
            resetDate: now.addingTimeInterval(3600),
            details: [detail]
        )
        let quota = ProviderQuota(
            providerId: "test",
            providerName: "Test Provider",
            headline: "42% · resets in 1h",
            lines: [line],
            lastUpdated: now
        )

        XCTAssertEqual(quota.providerId, "test")
        XCTAssertEqual(quota.providerName, "Test Provider")
        XCTAssertEqual(quota.headline, "42% · resets in 1h")
        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].percentage, 42)
        XCTAssertEqual(quota.lines[0].details?.first?.label, "RPM")
        XCTAssertEqual(quota.lastUpdated, now)
        XCTAssertNil(quota.error)
    }

    func testUsageLine_defaultsToNilForOptionalFields() {
        let line = UsageLine(label: "requests")

        XCTAssertEqual(line.label, "requests")
        XCTAssertNil(line.used)
        XCTAssertNil(line.total)
        XCTAssertNil(line.percentage)
        XCTAssertNil(line.unit)
        XCTAssertNil(line.resetDate)
        XCTAssertNil(line.details)
    }

    func testProviderQuota_errorStoresMessage() {
        let quota = ProviderQuota(
            providerId: "test",
            providerName: "Test",
            headline: "Error",
            lines: [],
            lastUpdated: Date(),
            error: "401 Unauthorized"
        )

        XCTAssertEqual(quota.error, "401 Unauthorized")
    }

    func testUsageDetail_roundtripsLabelAndValue() {
        let detail = UsageDetail(label: "RPM", value: "42 / 500")

        XCTAssertEqual(detail.label, "RPM")
        XCTAssertEqual(detail.value, "42 / 500")
    }

    // MARK: - ProviderInfo (ui 05 AC1)

    func testProviderInfo_includesAuthShape() throws {
        let info = try ProviderInfo(
            id: "test",
            displayName: "Test",
            description: "Desc",
            defaultBaseURL: XCTUnwrap(URL(string: "https://example.com")),
            authShape: .apiKeyFree
        )
        XCTAssertEqual(info.id, "test")
        XCTAssertEqual(info.authShape, .apiKeyFree)
    }

    func testProviderInfo_authShapeDefaultsToApiKey_whenSetExplicitly() throws {
        let info = try ProviderInfo(
            id: "test",
            displayName: "Test",
            description: "Desc",
            defaultBaseURL: XCTUnwrap(URL(string: "https://example.com")),
            authShape: .apiKey
        )
        XCTAssertEqual(info.authShape, .apiKey)
    }

    // MARK: - ProviderSetupError (ui 05)

    func testProviderSetupError_notSupported_isEquatable() {
        XCTAssertEqual(
            ProviderSetupError.notSupported,
            ProviderSetupError.notSupported
        )
    }

    func testProviderSetupError_notSupported_hasLocalizedDescription() {
        let error = ProviderSetupError.notSupported
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }
}
