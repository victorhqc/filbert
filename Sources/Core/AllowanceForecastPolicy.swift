import Foundation

public struct AllowanceForecastPolicy: Equatable, Sendable {
    public var recentHorizon: TimeInterval
    /// Used only to reach the minimum consumption.
    public var maximumHorizon: TimeInterval
    public var minimumObservationCount: Int
    public var minimumEvidenceSpan: TimeInterval
    public var minimumConsumptionSteps: Decimal
    public var minimumQuietThreshold: TimeInterval
    public var learningDisplayLimit: TimeInterval
    public var maximumGap: TimeInterval
    public var tooFarApartIntervalCount: Int
    public var resetTolerance: TimeInterval
    public var futureTimestampTolerance: TimeInterval
    public var maximumRetainedObservations: Int

    public static let standard = AllowanceForecastPolicy(
        recentHorizon: 30 * 60,
        maximumHorizon: 2 * 60 * 60,
        minimumObservationCount: 3,
        minimumEvidenceSpan: 10 * 60,
        minimumConsumptionSteps: 2,
        minimumQuietThreshold: 15 * 60,
        learningDisplayLimit: 2 * 60 * 60,
        maximumGap: 15 * 60,
        tooFarApartIntervalCount: 2,
        resetTolerance: 60,
        futureTimestampTolerance: 60,
        maximumRetainedObservations: 256
    )

    public init(
        recentHorizon: TimeInterval,
        maximumHorizon: TimeInterval,
        minimumObservationCount: Int,
        minimumEvidenceSpan: TimeInterval,
        minimumConsumptionSteps: Decimal,
        minimumQuietThreshold: TimeInterval,
        learningDisplayLimit: TimeInterval,
        maximumGap: TimeInterval,
        tooFarApartIntervalCount: Int,
        resetTolerance: TimeInterval,
        futureTimestampTolerance: TimeInterval,
        maximumRetainedObservations: Int
    ) {
        self.recentHorizon = recentHorizon
        self.maximumHorizon = maximumHorizon
        self.minimumObservationCount = minimumObservationCount
        self.minimumEvidenceSpan = minimumEvidenceSpan
        self.minimumConsumptionSteps = minimumConsumptionSteps
        self.minimumQuietThreshold = minimumQuietThreshold
        self.learningDisplayLimit = learningDisplayLimit
        self.maximumGap = maximumGap
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

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
