@testable import Core
import Foundation
import XCTest

final class SmartRefreshPolicyTests: XCTestCase {
    func testFirstSuccessEstablishesSlowBaseline() {
        var policy = SmartRefreshPolicy()

        XCTAssertEqual(policy.recordSuccess(quota(percentage: 10), for: "provider"), .slow)
        XCTAssertEqual(policy.cadence(for: "provider"), .slow)
    }

    func testChangeEntersAndSustainsFastMode() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(percentage: 10), for: "provider")

        XCTAssertEqual(policy.recordSuccess(quota(percentage: 20), for: "provider"), .fast)
        XCTAssertEqual(policy.recordSuccess(quota(percentage: 30), for: "provider"), .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
    }

    func testThreeUnchangedFastChecksReturnToSlow() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(percentage: 10), for: "provider")
        _ = policy.recordSuccess(quota(percentage: 20), for: "provider")

        XCTAssertEqual(policy.recordSuccess(quota(percentage: 20), for: "provider"), .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 1)
        XCTAssertEqual(policy.recordSuccess(quota(percentage: 20), for: "provider"), .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 2)
        XCTAssertEqual(policy.recordSuccess(quota(percentage: 20), for: "provider"), .slow)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
    }

    func testChangedFastResultResetsUnchangedCount() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(percentage: 10), for: "provider")
        _ = policy.recordSuccess(quota(percentage: 20), for: "provider")
        _ = policy.recordSuccess(quota(percentage: 20), for: "provider")

        XCTAssertEqual(policy.recordSuccess(quota(percentage: 30), for: "provider"), .fast)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
    }

    func testFailurePreservesBaselineAndReturnsToSlow() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(percentage: 10), for: "provider")
        _ = policy.recordSuccess(quota(percentage: 20), for: "provider")

        XCTAssertEqual(policy.recordFailure(for: "provider"), .slow)
        XCTAssertEqual(policy.consecutiveUnchangedChecks(for: "provider"), 0)
        XCTAssertEqual(policy.recordSuccess(quota(percentage: 20), for: "provider"), .slow)
        XCTAssertEqual(policy.recordSuccess(quota(percentage: 30), for: "provider"), .fast)
    }

    func testSnapshotIgnoresOrderingAndPresentationFields() {
        var policy = SmartRefreshPolicy()
        let resetDate = Date(timeIntervalSince1970: 1000)
        let first = ProviderQuota(
            providerId: "provider",
            providerName: "First name",
            headline: "First headline",
            lines: [
                UsageLine(
                    label: "Secondary",
                    used: 2,
                    total: 10,
                    percentage: 20,
                    unit: "requests",
                    resetDate: resetDate,
                    details: [UsageDetail(label: "B", value: "2"), UsageDetail(label: "A", value: "1")]
                ),
                UsageLine(label: "Primary", percentage: 10),
            ],
            lastUpdated: Date(timeIntervalSince1970: 1),
            error: "old error",
            isStale: true
        )
        let second = ProviderQuota(
            providerId: "provider",
            providerName: "Second name",
            headline: "Second headline",
            lines: [
                UsageLine(label: "Primary", percentage: 10),
                UsageLine(
                    label: "Secondary",
                    used: 2,
                    total: 10,
                    percentage: 20,
                    unit: "requests",
                    resetDate: resetDate,
                    details: [UsageDetail(label: "A", value: "1"), UsageDetail(label: "B", value: "2")]
                ),
            ],
            lastUpdated: Date(timeIntervalSince1970: 2),
            error: nil,
            isStale: false
        )

        _ = policy.recordSuccess(first, for: "provider")

        XCTAssertEqual(policy.recordSuccess(second, for: "provider"), .slow)
    }

    func testMeaningfulUsageChangesAreDetectedAndProviderStateIsIsolated() {
        var policy = SmartRefreshPolicy()
        _ = policy.recordSuccess(quota(percentage: 10), for: "first")
        _ = policy.recordSuccess(quota(percentage: 10), for: "second")

        XCTAssertEqual(policy.recordSuccess(quota(percentage: 20), for: "first"), .fast)
        XCTAssertEqual(policy.cadence(for: "second"), .slow)
        XCTAssertEqual(
            policy.recordSuccess(
                quota(percentage: 10, resetDate: Date(timeIntervalSince1970: 100)),
                for: "second"
            ),
            .fast
        )
    }

    private func quota(
        percentage: Double,
        resetDate: Date? = nil
    ) -> ProviderQuota {
        ProviderQuota(
            providerId: "provider",
            providerName: "Provider",
            headline: "\(percentage)%",
            lines: [UsageLine(label: "Usage", percentage: percentage, resetDate: resetDate)],
            lastUpdated: Date()
        )
    }
}
