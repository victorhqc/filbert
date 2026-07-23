import Foundation

/// Prevents scheduled refreshes from repeatedly hitting Cursor while the
/// undocumented endpoint is rate-limiting the provider.
actor CursorRateLimitBackoff {
    private let baseDelay: TimeInterval
    private let maximumDelay: TimeInterval
    private let now: @Sendable () -> Date

    private var consecutiveRateLimits = 0
    private var nextAllowedRequest: Date?

    init(
        baseDelay: TimeInterval = 300,
        maximumDelay: TimeInterval = 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.now = now
    }

    func checkRequestAllowed() throws {
        guard let nextAllowedRequest, now() < nextAllowedRequest else { return }
        throw CursorError.http(429)
    }

    func recordRateLimit() {
        let exponent = min(consecutiveRateLimits, 10)
        let delay = min(
            baseDelay * pow(2, Double(exponent)),
            maximumDelay
        )
        consecutiveRateLimits += 1
        nextAllowedRequest = now().addingTimeInterval(delay)
    }

    func recordSuccessfulResponse() {
        consecutiveRateLimits = 0
        nextAllowedRequest = nil
    }
}
