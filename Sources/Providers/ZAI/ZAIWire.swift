import Core
import Foundation

// MARK: - Wire types (internal to this module only)

enum ZAILimitType: String {
    case tokens = "TOKENS_LIMIT"
    case credits = "CREDIT_LIMIT"
    case time = "TIME_LIMIT"
}

struct ZAIQuotaResponse: Decodable {
    let data: ZAIData
}

struct ZAIData: Decodable {
    let limits: [ZAILimit]
}

struct ZAILimit: Decodable {
    let type: String
    let unit: Int
    let number: Int?
    let percentage: Double?
    let usage: Double?
    let currentValue: Double?
    let remaining: Double?
    let nextResetTime: Int64?
    let usageDetails: [ZAIUsageDetail]?
}

struct ZAIUsageDetail: Decodable {
    let modelCode: String
    let usage: Double?
}

struct ZAISubscriptionResponse: Decodable {
    let data: [ZAISubscription]?
}

struct ZAISubscription: Decodable {
    let status: String?
    let version: String?
}

// MARK: - Window recognition

struct ZAIWindowDescriptor {
    let label: String
    let windowDuration: TimeInterval?
    let isFiveHour: Bool
    let isWeekly: Bool

    static func recognize(_ limit: ZAILimit) -> ZAIWindowDescriptor? {
        switch ZAILimitType(rawValue: limit.type) {
        case .tokens, .credits:
            switch limit.unit {
            case 3:
                let hours = max(limit.number ?? 5, 1)
                return ZAIWindowDescriptor(
                    label: String.localizedStringWithFormat(
                        String(localized: "%lld-hour window"),
                        hours
                    ),
                    windowDuration: TimeInterval(hours) * 3600,
                    isFiveHour: true,
                    isWeekly: false
                )
            case 6:
                return ZAIWindowDescriptor(
                    label: String(localized: "Weekly"),
                    windowDuration: UsageWindowDuration.week,
                    isFiveHour: false,
                    isWeekly: true
                )
            default:
                return nil
            }
        case .time:
            guard limit.unit == 5, limit.number == nil || limit.number == 1 else {
                return nil
            }
            return ZAIWindowDescriptor(
                label: String(localized: "Monthly web-tool calls"),
                windowDuration: nil,
                isFiveHour: false,
                isWeekly: false
            )
        case nil:
            return nil
        }
    }
}
