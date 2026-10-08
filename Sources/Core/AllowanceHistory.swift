import Foundation

struct AllowanceSample: Equatable, Sendable {
    let value: Decimal
    let time: Date
    let isApproximate: Bool
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
    private(set) var segmentStart: Date
    private(set) var lastConsumptionAt: Date
    private(set) var lastUsableRate: Decimal?
    private(set) var consecutiveLongIntervals = 0
    private(set) var isInterrupted = false

    init(baseline: AllowanceSample, descriptor: AllowanceForecastDescriptor) {
        self.descriptor = descriptor
        samples = [baseline]
        segmentStart = baseline.time
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
        if isInterrupted {
            consecutiveLongIntervals = 0
            rebaseline(at: sample, descriptor: newDescriptor)
            return
        }

        let previous = latest
        guard sample.time > previous.time else { return }

        let interval = sample.time.timeIntervalSince(previous.time)
        consecutiveLongIntervals = interval > policy.maximumGap ? consecutiveLongIntervals + 1 : 0
        guard interval <= policy.maximumGap,
              continuesPeriod(with: newDescriptor, at: sample.time, policy: policy),
              consumed(from: previous, to: sample) >= 0
        else {
            rebaseline(at: sample, descriptor: newDescriptor)
            return
        }

        let wasQuiet = isQuiet(policy: policy)
        let showsConsumption = consumed(from: previous, to: sample) > 0
        descriptor = newDescriptor
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

    mutating func interrupt() {
        isInterrupted = true
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
            isApproximate: usesEstimate ? estimate?.isApproximate ?? false : latest.isApproximate
        )
    }

    /// Endpoint delta over the recent horizon. It reaches further back only
    /// to meet the minimum consumption. Intermediate samples never count.
    func rateEstimate(policy: AllowanceForecastPolicy) -> AllowanceRateEstimate? {
        let latest = latest
        let minimumConsumption = policy.minimumConsumptionSteps * descriptor.resolution
        let recentCutoff = latest.time.addingTimeInterval(-policy.recentHorizon)
        let maximumCutoff = latest.time.addingTimeInterval(-policy.maximumHorizon)
        guard let earliestIndex = samples.firstIndex(where: { $0.time >= maximumCutoff }) else { return nil }

        var startIndex = max(samples.lastIndex { $0.time <= recentCutoff } ?? earliestIndex, earliestIndex)
        while startIndex > earliestIndex, consumed(from: samples[startIndex], to: latest) < minimumConsumption {
            startIndex -= 1
        }

        let start = samples[startIndex]
        let consumption = consumed(from: start, to: latest)
        let span = latest.time.timeIntervalSince(start.time)
        guard samples.endIndex - startIndex >= policy.minimumObservationCount,
              span >= policy.minimumEvidenceSpan,
              span > 0,
              consumption >= minimumConsumption,
              consumption > 0
        else {
            return nil
        }
        return AllowanceRateEstimate(
            ratePerSecond: consumption / Decimal(span),
            span: span,
            isApproximate: samples[startIndex...].contains { $0.isApproximate }
        )
    }
}

private extension AllowanceHistory {
    func state(
        at now: Date,
        estimate: AllowanceRateEstimate?,
        policy: AllowanceForecastPolicy
    ) -> AllowanceForecast.State {
        if isInterrupted {
            return .paused
        }
        let remaining = remaining(at: latest)
        if remaining <= 0 {
            return .exhausted
        }
        if consecutiveLongIntervals >= policy.tooFarApartIntervalCount {
            return .tooFarApart
        }
        if isEvidenceStale(at: now, policy: policy) {
            return .paused
        }
        if isQuiet(policy: policy) {
            return .quiet
        }
        guard let estimate else {
            return now.timeIntervalSince(segmentStart) < policy.learningDisplayLimit ? .learning : .insufficient
        }

        let depletesAt = latest.time.addingTimeInterval((remaining / estimate.ratePerSecond).doubleValue)
        if case let .fixedPeriod(_, resetsAt) = descriptor.accounting, depletesAt >= resetsAt {
            return .beyondReset(resetsAt: resetsAt)
        }
        // Only a provider measurement can report exhaustion.
        return now >= depletesAt ? .paused : .estimated(depletesAt: depletesAt)
    }

    func isEvidenceStale(at now: Date, policy: AllowanceForecastPolicy) -> Bool {
        let age = now.timeIntervalSince(latest.time)
        if age > policy.maximumGap || age < -policy.futureTimestampTolerance {
            return true
        }
        if case let .fixedPeriod(_, resetsAt) = descriptor.accounting, now >= resetsAt {
            return true
        }
        return false
    }

    /// Needs a prior rate. A slow allowance is never quiet during active work.
    func isQuiet(policy: AllowanceForecastPolicy) -> Bool {
        guard let lastUsableRate else { return false }
        let threshold = policy.quietThreshold(resolution: descriptor.resolution, ratePerSecond: lastUsableRate)
        return latest.time.timeIntervalSince(lastConsumptionAt) >= threshold
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
            return oldLimit == newLimit
                && oldResetsAt > time
                && abs(newResetsAt.timeIntervalSince(oldResetsAt)) <= policy.resetTolerance
        case (.balance, .fixedPeriod), (.fixedPeriod, .balance):
            return false
        }
    }

    /// Negative values are corrections or top-ups, never consumption.
    func consumed(from earlier: AllowanceSample, to later: AllowanceSample) -> Decimal {
        switch descriptor.accounting {
        case .fixedPeriod:
            later.value - earlier.value
        case .balance:
            earlier.value - later.value
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
        segmentStart = sample.time
        lastConsumptionAt = sample.time
        lastUsableRate = nil
        isInterrupted = false
    }

    mutating func startSegment(at sample: AllowanceSample) {
        samples = [sample]
        segmentStart = sample.time
    }

    mutating func append(_ sample: AllowanceSample, policy: AllowanceForecastPolicy) {
        samples.append(sample)
        let cutoff = sample.time.addingTimeInterval(-policy.maximumHorizon)
        if let firstRetained = samples.firstIndex(where: { $0.time >= cutoff }), firstRetained > 0 {
            samples.removeFirst(firstRetained)
        }
        if samples.count > policy.maximumRetainedObservations {
            samples.removeFirst(samples.count - policy.maximumRetainedObservations)
        }
    }
}
