import Core
@testable import DeepSeekProvider
import XCTest

final class DeepSeekCaptureReplayTests: XCTestCase {
    private struct Read: Decodable {
        let receivedAt: TimeInterval
        let response: DeepSeekBalanceResponse
    }

    private let singleCharge = "deepseek-capture-single-charge"
    private let chargeFinishedAt = Date(timeIntervalSince1970: 1_791_882_605.418)
    private let lineId = "total-balance-usd"

    func testEveryAmountHasTwoDecimalsLikeTheResolution() throws {
        let amounts = try reads(singleCharge).flatMap { read in
            read.response.balanceInfos.flatMap { [$0.totalBalance, $0.grantedBalance, $0.toppedUpBalance] }
        }

        XCTAssertFalse(amounts.isEmpty)
        XCTAssertTrue(amounts.allSatisfy { $0.range(of: #"^\d+\.\d{2}$"#, options: .regularExpression) != nil })
        XCTAssertEqual(DeepSeekProvider.balanceResolution, cents(1))
    }

    func testTheChargeReachesTheBalanceAboutThreeMinutesLaterInOneStep() throws {
        let quotas = try replay(singleCharge)
        let drop = try XCTUnwrap(firstDrop(in: quotas))

        XCTAssertEqual(number(in: quotas[drop - 1]), cents(1293))
        XCTAssertEqual(Set(quotas[drop...].compactMap(number(in:))), [cents(1285)])
        XCTAssertGreaterThan(quotas[drop - 1].lastUpdated.timeIntervalSince(chargeFinishedAt), 170)
        XCTAssertLessThan(quotas[drop].lastUpdated.timeIntervalSince(chargeFinishedAt), 210)
    }

    func testASingleChargeLearnsThenEstimatesUntilItTurnsQuiet() throws {
        let quotas = try replay(singleCharge)
        let states = states(in: quotas)
        let drop = try XCTUnwrap(firstDrop(in: quotas))
        let segmentStart = quotas[drop - 1].lastUpdated
        let dropReadAt = quotas[drop].lastUpdated

        XCTAssertTrue(states[..<drop].allSatisfy { $0 == .insufficient })
        XCTAssertGreaterThan(try XCTUnwrap(quotas.last).lastUpdated.timeIntervalSince(dropReadAt), 15 * 60)
        for index in drop ..< quotas.count {
            let time = quotas[index].lastUpdated
            if time.timeIntervalSince(segmentStart) < 10 * 60 {
                XCTAssertEqual(states[index], .learning, "read \(index)")
            } else if time.timeIntervalSince(dropReadAt) < 15 * 60 {
                guard case .estimated? = states[index] else {
                    return XCTFail("Expected an estimate at read \(index), got \(String(describing: states[index]))")
                }
            } else {
                XCTAssertEqual(states[index], .quiet, "read \(index)")
            }
        }
    }

    private func cents(_ amount: Int) -> Decimal {
        Decimal(amount) / 100
    }

    private func firstDrop(in quotas: [ProviderQuota]) -> Int? {
        quotas.indices.dropFirst().first { index in
            guard let balance = number(in: quotas[index]), let previous = number(in: quotas[index - 1]) else {
                return false
            }
            return balance < previous
        }
    }

    private func reads(_ fixture: String) throws -> [Read] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
        return try JSONDecoder().decode([Read].self, from: Data(contentsOf: url))
    }

    private func replay(_ fixture: String) throws -> [ProviderQuota] {
        let provider = DeepSeekProvider()
        return try reads(fixture).map { read in
            provider.map(read.response, receivedAt: Date(timeIntervalSince1970: read.receivedAt))
        }
    }

    private func number(in quota: ProviderQuota) -> Decimal? {
        guard case let .number(value)? = quota.activityObservation?.metrics.first(where: { $0.id == lineId })?.value
        else {
            return nil
        }
        return value
    }

    private func states(in quotas: [ProviderQuota]) -> [AllowanceForecast.State?] {
        let providerId = DeepSeekProvider.providerId
        var forecaster = AllowanceForecaster()
        return quotas.map { quota in
            forecaster.record(quota.activityObservation, isStale: false, for: providerId, at: quota.lastUpdated)
            return forecaster.forecasts(for: providerId, at: quota.lastUpdated)[lineId]?.state
        }
    }
}
