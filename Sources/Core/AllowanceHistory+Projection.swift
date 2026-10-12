import Foundation

extension AllowanceHistory {
    func periodAverageEstimate(policy: AllowanceForecastPolicy) -> AllowanceRateEstimate? {
        guard case let .fixedPeriod(_, resetsAt, length) = descriptor.accounting else { return nil }
        let elapsed = latest.time.timeIntervalSince(resetsAt.addingTimeInterval(-length))
        guard elapsed >= policy.longPeriodWarmUp else { return nil }
        return AllowanceRateEstimate(
            ratePerSecond: latest.value / Decimal(elapsed),
            span: elapsed,
            isApproximate: latest.isApproximate
        )
    }

    func isLongPeriod(policy: AllowanceForecastPolicy) -> Bool {
        guard case let .fixedPeriod(_, _, length) = descriptor.accounting else { return false }
        return length > policy.longPeriodThreshold
    }

    func longPeriodState(
        at now: Date,
        estimate: AllowanceRateEstimate?,
        remaining: Decimal,
        policy: AllowanceForecastPolicy
    ) -> AllowanceForecast.State {
        let age = now.timeIntervalSince(latest.time)
        guard age <= policy.longPeriodMaximumObservationAge, age >= -policy.futureTimestampTolerance else {
            return .paused
        }
        guard let estimate else { return .insufficient }
        guard let depletesAt = projectedDepletion(of: remaining, at: estimate) else {
            return descriptor.accounting.resetsAt.map { .beyondReset(resetsAt: $0) } ?? .insufficient
        }
        return projectedState(depletesAt: depletesAt, at: now)
    }

    func projectedState(depletesAt: Date, at now: Date) -> AllowanceForecast.State {
        if let resetsAt = descriptor.accounting.resetsAt, depletesAt >= resetsAt {
            return .beyondReset(resetsAt: resetsAt)
        }
        // Only a provider measurement can report exhaustion.
        return now >= depletesAt ? .paused : .estimated(depletesAt: depletesAt)
    }

    func projectedDepletion(of remaining: Decimal, at estimate: AllowanceRateEstimate) -> Date? {
        guard estimate.ratePerSecond > 0 else { return nil }
        let duration = (remaining / estimate.ratePerSecond).doubleValue
        guard duration.isFinite else { return nil }
        return latest.time.addingTimeInterval(duration)
    }
}

extension AllowanceForecastDescriptor.Accounting {
    var resetsAt: Date? {
        guard case let .fixedPeriod(_, resetsAt, _) = self else { return nil }
        return resetsAt
    }
}
