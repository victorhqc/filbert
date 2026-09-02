import Foundation

struct GeminiClientMetadata: Encodable, Sendable {
    let ideType: String
    let platform: String
    let pluginType: String
    let duetProject: String?

    enum CodingKeys: String, CodingKey {
        case ideType
        case platform
        case pluginType
        case duetProject
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ideType, forKey: .ideType)
        try container.encode(platform, forKey: .platform)
        try container.encode(pluginType, forKey: .pluginType)
        try container.encodeIfPresent(duetProject, forKey: .duetProject)
    }
}

struct GeminiLoadCodeAssistRequest: Encodable, Sendable {
    let cloudaicompanionProject: String?
    let metadata: GeminiClientMetadata

    enum CodingKeys: String, CodingKey {
        case cloudaicompanionProject
        case metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(
            cloudaicompanionProject,
            forKey: .cloudaicompanionProject
        )
        try container.encode(metadata, forKey: .metadata)
    }
}

struct GeminiLoadCodeAssistResponse: Decodable, Sendable {
    let cloudaicompanionProject: GeminiProjectReference?
    let currentCloudaicompanionProject: GeminiProjectReference?

    var projectIdentifier: String? {
        cloudaicompanionProject?.value
            ?? currentCloudaicompanionProject?.value
    }
}

enum GeminiProjectReference: Decodable, Sendable {
    case string(String)
    case object(id: String?, projectId: String?)

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self = .string(value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try .object(
            id: container.decodeIfPresent(String.self, forKey: .id),
            projectId: container.decodeIfPresent(String.self, forKey: .projectId)
        )
    }

    var value: String? {
        let candidates: [String?] = switch self {
        case let .string(value):
            [value]
        case let .object(id, projectId):
            [id, projectId]
        }
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectId
    }
}
