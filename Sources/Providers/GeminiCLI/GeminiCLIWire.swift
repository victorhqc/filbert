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
    let cloudaicompanionProject: String?
}
