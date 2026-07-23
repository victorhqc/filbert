import Foundation

struct LegacyClaudeBrandConfiguration: Sendable {
    let helperURL: URL
    let cacheURL: URL
    let chainStart: String
    let chainSeparator: String

    static let production = LegacyClaudeBrandConfiguration(
        helperURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("ai-usage-statusline"),
        cacheURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("ai-usage")
            .appendingPathComponent("claude-code.json"),
        chainStart: "###AI-USAGE-CHAIN-START###",
        chainSeparator: "###AI-USAGE-CHAIN-SEPARATOR###"
    )
}
