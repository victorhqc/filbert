import Foundation

public struct SmartRefreshPolicy: Sendable {
    public enum Cadence: Equatable, Sendable {
        case slow
        case fast
    }

    private var states: [String: State] = [:]

    public init() {}

    @discardableResult
    public mutating func recordSuccess(
        _ quota: ProviderQuota,
        for providerId: String
    ) -> Cadence {
        let snapshot = UsageSnapshot(quota: quota)
        var state = states[providerId] ?? State()

        guard let previousSnapshot = state.snapshot else {
            state.snapshot = snapshot
            states[providerId] = state
            return state.cadence
        }

        state.snapshot = snapshot
        guard previousSnapshot != snapshot else {
            if state.cadence == .fast {
                state.consecutiveUnchangedChecks += 1
                if state.consecutiveUnchangedChecks == Self.unchangedChecksBeforeSlowing {
                    state.cadence = .slow
                    state.consecutiveUnchangedChecks = 0
                }
            }
            states[providerId] = state
            return state.cadence
        }

        state.cadence = .fast
        state.consecutiveUnchangedChecks = 0
        states[providerId] = state
        return state.cadence
    }

    @discardableResult
    public mutating func recordFailure(for providerId: String) -> Cadence {
        var state = states[providerId] ?? State()
        state.cadence = .slow
        state.consecutiveUnchangedChecks = 0
        states[providerId] = state
        return state.cadence
    }

    public mutating func reset(for providerId: String) {
        states.removeValue(forKey: providerId)
    }

    public mutating func resetAll() {
        states.removeAll()
    }

    public func cadence(for providerId: String) -> Cadence {
        states[providerId]?.cadence ?? .slow
    }

    public func consecutiveUnchangedChecks(for providerId: String) -> Int {
        states[providerId]?.consecutiveUnchangedChecks ?? 0
    }

    private static let unchangedChecksBeforeSlowing = 3
}

private extension SmartRefreshPolicy {
    struct State: Sendable {
        var snapshot: UsageSnapshot?
        var cadence: Cadence = .slow
        var consecutiveUnchangedChecks = 0
    }

    struct UsageSnapshot: Equatable, Sendable {
        let lines: [UsageLineSnapshot]

        init(quota: ProviderQuota) {
            lines = quota.lines.map(UsageLineSnapshot.init).sorted()
        }
    }

    struct UsageLineSnapshot: Equatable, Comparable, Sendable {
        let label: String
        let used: Double?
        let total: Double?
        let percentage: Double?
        let unit: String?
        let resetDate: Date?
        let details: [UsageDetailSnapshot]

        init(line: UsageLine) {
            label = line.label
            used = line.used
            total = line.total
            percentage = line.percentage
            unit = line.unit
            resetDate = line.resetDate
            details = (line.details ?? []).map(UsageDetailSnapshot.init).sorted()
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.label != rhs.label {
                return lhs.label < rhs.label
            }
            if lhs.used != rhs.used {
                return optionalLess(lhs.used, rhs.used)
            }
            if lhs.total != rhs.total {
                return optionalLess(lhs.total, rhs.total)
            }
            if lhs.percentage != rhs.percentage {
                return optionalLess(lhs.percentage, rhs.percentage)
            }
            if lhs.unit != rhs.unit {
                return optionalLess(lhs.unit, rhs.unit)
            }
            if lhs.resetDate != rhs.resetDate {
                return optionalLess(lhs.resetDate, rhs.resetDate)
            }
            for (leftDetail, rightDetail) in zip(lhs.details, rhs.details) where leftDetail != rightDetail {
                return leftDetail < rightDetail
            }
            return lhs.details.count < rhs.details.count
        }

        private static func optionalLess<Value: Comparable>(
            _ lhs: Value?,
            _ rhs: Value?
        ) -> Bool {
            switch (lhs, rhs) {
            case (.none, .some): true
            case (.some, .none): false
            case let (.some(left), .some(right)): left < right
            case (.none, .none): false
            }
        }
    }

    struct UsageDetailSnapshot: Equatable, Comparable, Sendable {
        let label: String
        let value: String

        init(detail: UsageDetail) {
            label = detail.label
            value = detail.value
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.label == rhs.label ? lhs.value < rhs.value : lhs.label < rhs.label
        }
    }
}
