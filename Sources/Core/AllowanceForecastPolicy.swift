import Foundation

struct AllowanceForecastPolicy: Equatable, Sendable {
    static let standard = AllowanceForecastPolicy()

    let recentHorizon: TimeInterval
    let maximumHorizon: TimeInterval
    let minimumObservationCount: Int
    let minimumEvidenceSpan: TimeInterval
    let minimumConsumptionSteps: Decimal
    let minimumQuietThreshold: TimeInterval
    let maximumGap: TimeInterval
    let maximumObservationAge: TimeInterval
    let tooFarApartIntervalCount: Int
    let resetTolerance: TimeInterval
    let futureTimestampTolerance: TimeInterval
    let maximumRetainedObservations: Int

    init(
        recentHorizon: TimeInterval = 30 * 60,
        maximumHorizon: TimeInterval = 2 * 60 * 60,
        minimumObservationCount: Int = 3,
        minimumEvidenceSpan: TimeInterval = 10 * 60,
        minimumConsumptionSteps: Decimal = 2,
        minimumQuietThreshold: TimeInterval = 15 * 60,
        maximumGap: TimeInterval = 30 * 60,
        maximumObservationAge: TimeInterval = 30 * 60,
        tooFarApartIntervalCount: Int = 2,
        resetTolerance: TimeInterval = 60,
        futureTimestampTolerance: TimeInterval = 60,
        maximumRetainedObservations: Int = 256
    ) {
        precondition(maximumRetainedObservations >= 2, "A rate needs at least two retained observations")
        self.recentHorizon = recentHorizon
        self.maximumHorizon = maximumHorizon
        self.minimumObservationCount = minimumObservationCount
        self.minimumEvidenceSpan = minimumEvidenceSpan
        self.minimumConsumptionSteps = minimumConsumptionSteps
        self.minimumQuietThreshold = minimumQuietThreshold
        self.maximumGap = maximumGap
        self.maximumObservationAge = maximumObservationAge
        self.tooFarApartIntervalCount = tooFarApartIntervalCount
        self.resetTolerance = resetTolerance
        self.futureTimestampTolerance = futureTimestampTolerance
        self.maximumRetainedObservations = maximumRetainedObservations
    }

    func quietThreshold(resolution: Decimal, ratePerSecond: Decimal) -> TimeInterval {
        let stepDuration = (resolution / ratePerSecond).doubleValue
        return min(max(2 * stepDuration, minimumQuietThreshold), maximumHorizon)
    }
}
