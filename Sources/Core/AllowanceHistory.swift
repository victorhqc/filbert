import Foundation

struct AllowanceSample: Equatable, Sendable {
    let value: Decimal
    let time: Date
    let isApproximate: Bool
    /// Accepted observations since the previous stored sample, this one included.
    var observationCount = 1
}

extension AllowanceSample {
    init?(
        metric: ProviderActivityMetric,
        descriptor: AllowanceForecastDescriptor,
        now: Date,
        policy: AllowanceForecastPolicy
    ) {
        guard case let .number(value) = metric.value,
              value.isFinite,
              descriptor.resolution.isFinite,
              descriptor.resolution > 0,
              !descriptor.usageLineId.isEmpty,
              descriptor.timing.date.timeIntervalSince(now) <= policy.futureTimestampTolerance
        else {
            return nil
        }
        switch descriptor.accounting {
        case let .fixedPeriod(limit, resetsAt):
            guard limit.isFinite, limit > 0, value >= 0, resetsAt > descriptor.timing.date else { return nil }
        case .balance:
            break
        }
        if case let .currency(code) = descriptor.unit, code.isEmpty {
            return nil
        }
        self.init(value: value, time: descriptor.timing.date, isApproximate: descriptor.timing.isApproximate)
    }
}

struct AllowanceRateEstimate: Equatable, Sendable {
    let ratePerSecond: Decimal
    let span: TimeInterval
    let isApproximate: Bool
}

/// `samples` is never empty. It never spans a period boundary, a gap, or a
/// quiet period.
struct AllowanceHistory: Sendable {
    private(set) var descriptor: AllowanceForecastDescriptor
    private(set) var samples: [AllowanceSample]
    private(set) var baselineAt: Date
    private(set) var periodResetsAt: Date?
    private(set) var lastConsumptionAt: Date
    private(set) var lastUsableRate: Decimal?
    private(set) var consecutiveLongIntervals = 0
    private(set) var lastLongInterval: TimeInterval = 0
    private(set) var interruptedAt: Date?
    private(set) var isPaused = false

    init(baseline: AllowanceSample, descriptor: AllowanceForecastDescriptor) {
        self.descriptor = descriptor
        samples = [baseline]
        baselineAt = baseline.time
        periodResetsAt = descriptor.accounting.resetsAt
        lastConsumptionAt = baseline.time
    }

    var latest: AllowanceSample {
        samples[samples.endIndex - 1]
    }

    mutating func record(
        _ sample: AllowanceSample,
        descriptor newDescriptor: AllowanceForecastDescriptor,
        policy: AllowanceForecastPolicy
    ) {
        if let interruptedAt {
            guard sample.time > interruptedAt else { return }
            consecutiveLongIntervals = 0
            rebaseline(at: sample, descriptor: newDescriptor)
            return
        }

        let previous = latest
        guard sample.time > previous.time else { return }

        let interval = sample.time.timeIntervalSince(previous.time)
        if interval > policy.maximumGap {
            consecutiveLongIntervals += 1
            lastLongInterval = interval
        } else {
            consecutiveLongIntervals = 0
        }
        guard interval <= policy.maximumGap,
              continuesPeriod(with: newDescriptor, at: sample.time, policy: policy),
              consumed(from: previous, to: sample) >= 0
        else {
            rebaseline(at: sample, descriptor: newDescriptor)
            return
        }

        let wasQuiet = isQuiet(estimate: rateEstimate(policy: policy), policy: policy)
        let showsConsumption = consumed(from: previous, to: sample) > 0
        descriptor = newDescriptor
        isPaused = false
        if showsConsumption {
            if wasQuiet {
                startSegment(at: previous)
            }
            lastConsumptionAt = sample.time
        }
        append(sample, policy: policy)

        // Hold the rate between steps. Otherwise the quiet threshold drifts
        // as the window slides.
        if showsConsumption || lastUsableRate == nil, let estimate = rateEstimate(policy: policy) {
            lastUsableRate = estimate.ratePerSecond
        }
    }

    mutating func interrupt(at date: Date) {
        interruptedAt = max(interruptedAt ?? date, date)
    }

    mutating func pause() {
        isPaused = true
    }

    func forecast(at now: Date, policy: AllowanceForecastPolicy) -> AllowanceForecast {
        let estimate = rateEstimate(policy: policy)
        let state = state(at: now, estimate: estimate, policy: policy)
        let usesEstimate = switch state {
        case .estimated, .beyondReset: true
        default: false
        }
        return AllowanceForecast(
            usageLineId: descriptor.usageLineId,
            state: state,
            observedAt: latest.time,
            evidenceSpan: usesEstimate ? estimate?.span : nil,
            isApproximate: usesEstimate ? estimate?.isApproximate ?? false : latest.isApproximate,
            isUncertainNearLimit: isUncertainNearLimit(in: state, at: now, estimate: estimate, policy: policy)
        )
    }

    func rateEstimate(policy: AllowanceForecastPolicy) -> AllowanceRateEstimate? {
        let minimumConsumption = policy.minimumConsumptionSteps * descriptor.resolution
        var horizon = policy.recentHorizon
        var window = rateWindow(spanning: horizon)
        while window.consumption < minimumConsumption, horizon < policy.maximumHorizon {
            horizon = min(horizon + policy.recentHorizon, policy.maximumHorizon)
            window = rateWindow(spanning: horizon)
        }

        let span = latest.time.timeIntervalSince(window.start)
        guard window.observationCount >= policy.minimumObservationCount,
              span >= policy.minimumEvidenceSpan,
              span > 0,
              window.consumption >= minimumConsumption,
              window.consumption > 0
        else {
            return nil
        }
        let rate = window.consumption / Decimal(span)
        guard rate.isFinite, rate > 0 else { return nil }
        return AllowanceRateEstimate(
            ratePerSecond: rate,
            span: span,
            isApproximate: samples[window.lowerIndex...].contains { $0.isApproximate }
        )
    }
}

private extension AllowanceHistory {
    struct Window {
        let start: Date
        let lowerIndex: Int
        let consumption: Decimal
        let observationCount: Int
    }

    func rateWindow(spanning horizon: TimeInterval) -> Window {
        let start = max(latest.time.addingTimeInterval(-horizon), samples[0].time)
        let lowerIndex = samples.lastIndex { $0.time <= start } ?? 0
        let lower = samples[lowerIndex]
        var startValue = lower.value
        if lower.time < start, lowerIndex + 1 < samples.endIndex {
            let upper = samples[lowerIndex + 1]
            let elapsed = Decimal(start.timeIntervalSince(lower.time))
            let duration = Decimal(upper.time.timeIntervalSince(lower.time))
            startValue += (upper.value - lower.value) * elapsed / duration
        }
        return Window(
            start: start,
            lowerIndex: lowerIndex,
            consumption: consumed(from: startValue, to: latest.value),
            observationCount: samples[(lowerIndex + 1)...].reduce(1) { $0 + $1.observationCount }
        )
    }

    func state(
        at now: Date,
        estimate: AllowanceRateEstimate?,
        policy: AllowanceForecastPolicy
    ) -> AllowanceForecast.State {
        if let resetsAt = descriptor.accounting.resetsAt, now >= resetsAt {
            return .paused
        }
        let remaining = remaining(at: latest)
        if remaining <= 0 {
            return .exhausted
        }
        if interruptedAt != nil || isPaused {
            return .paused
        }
        if consecutiveLongIntervals >= policy.tooFarApartIntervalCount {
            let age = now.timeIntervalSince(latest.time)
            return age < lastLongInterval + policy.maximumGap ? .tooFarApart : .paused
        }
        if isEvidenceStale(at: now, policy: policy) {
            return .paused
        }
        if isQuiet(estimate: estimate, policy: policy) {
            return .quiet
        }
        guard let estimate, let depletesAt = projectedDepletion(of: remaining, at: estimate) else {
            return now.timeIntervalSince(baselineAt) < policy.maximumHorizon ? .learning : .insufficient
        }

        if let resetsAt = descriptor.accounting.resetsAt, depletesAt >= resetsAt {
            return .beyondReset(resetsAt: resetsAt)
        }
        // Only a provider measurement can report exhaustion.
        return now >= depletesAt ? .paused : .estimated(depletesAt: depletesAt)
    }

    func isUncertainNearLimit(
        in state: AllowanceForecast.State,
        at now: Date,
        estimate: AllowanceRateEstimate?,
        policy: AllowanceForecastPolicy
    ) -> Bool {
        switch state {
        case .estimated, .beyondReset:
            return false
        case .learning, .quiet, .tooFarApart, .paused, .exhausted, .insufficient:
            break
        }
        if let resetsAt = descriptor.accounting.resetsAt, now >= resetsAt {
            return false
        }
        let remaining = remaining(at: latest)
        if remaining < policy.minimumConsumptionSteps * descriptor.resolution {
            return true
        }
        guard state == .paused,
              let estimate,
              let depletesAt = projectedDepletion(of: remaining, at: estimate)
        else {
            return false
        }
        return now >= depletesAt
    }

    func projectedDepletion(of remaining: Decimal, at estimate: AllowanceRateEstimate) -> Date? {
        let duration = (remaining / estimate.ratePerSecond).doubleValue
        guard duration.isFinite else { return nil }
        return latest.time.addingTimeInterval(duration)
    }

    func isEvidenceStale(at now: Date, policy: AllowanceForecastPolicy) -> Bool {
        let age = now.timeIntervalSince(latest.time)
        return age > policy.maximumObservationAge || age < -policy.futureTimestampTolerance
    }

    func isQuiet(estimate: AllowanceRateEstimate?, policy: AllowanceForecastPolicy) -> Bool {
        guard let lastUsableRate else { return false }
        let quietFor = latest.time.timeIntervalSince(lastConsumptionAt)
        if quietFor >= policy.quietThreshold(resolution: descriptor.resolution, ratePerSecond: lastUsableRate) {
            return true
        }
        return estimate == nil && quietFor >= policy.minimumQuietThreshold
    }

    func continuesPeriod(
        with newDescriptor: AllowanceForecastDescriptor,
        at time: Date,
        policy: AllowanceForecastPolicy
    ) -> Bool {
        guard newDescriptor.unit == descriptor.unit,
              newDescriptor.resolution == descriptor.resolution,
              newDescriptor.usageLineId == descriptor.usageLineId
        else {
            return false
        }
        switch (descriptor.accounting, newDescriptor.accounting) {
        case (.balance, .balance):
            return true
        case let (.fixedPeriod(oldLimit, oldResetsAt), .fixedPeriod(newLimit, newResetsAt)):
            guard let periodResetsAt else { return false }
            return oldLimit == newLimit
                && oldResetsAt > time
                && abs(newResetsAt.timeIntervalSince(periodResetsAt)) <= policy.resetTolerance
        case (.balance, .fixedPeriod), (.fixedPeriod, .balance):
            return false
        }
    }

    func consumed(from earlier: AllowanceSample, to later: AllowanceSample) -> Decimal {
        consumed(from: earlier.value, to: later.value)
    }

    func consumed(from earlier: Decimal, to later: Decimal) -> Decimal {
        switch descriptor.accounting {
        case .fixedPeriod:
            later - earlier
        case .balance:
            earlier - later
        }
    }

    func remaining(at sample: AllowanceSample) -> Decimal {
        switch descriptor.accounting {
        case let .fixedPeriod(limit, _):
            limit - sample.value
        case .balance:
            sample.value
        }
    }

    mutating func rebaseline(at sample: AllowanceSample, descriptor newDescriptor: AllowanceForecastDescriptor) {
        descriptor = newDescriptor
        samples = [sample]
        baselineAt = sample.time
        periodResetsAt = newDescriptor.accounting.resetsAt
        lastConsumptionAt = sample.time
        lastUsableRate = nil
        interruptedAt = nil
        isPaused = false
    }

    mutating func startSegment(at sample: AllowanceSample) {
        samples = [sample]
    }

    mutating func append(_ sample: AllowanceSample, policy: AllowanceForecastPolicy) {
        var sample = sample
        if samples.count >= 2, samples.suffix(2).allSatisfy({ $0.value == sample.value }) {
            sample.observationCount += samples.removeLast().observationCount
        }
        samples.append(sample)

        let cutoff = sample.time.addingTimeInterval(-policy.maximumHorizon)
        if let anchor = samples.lastIndex(where: { $0.time <= cutoff }), anchor > 0 {
            samples.removeFirst(anchor)
        }
        if samples.count > policy.maximumRetainedObservations {
            samples.removeFirst(samples.count - policy.maximumRetainedObservations)
        }
    }
}

private extension AllowanceForecastDescriptor.Accounting {
    var resetsAt: Date? {
        guard case let .fixedPeriod(_, resetsAt) = self else { return nil }
        return resetsAt
    }
}
