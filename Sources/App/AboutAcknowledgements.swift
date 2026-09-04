import Foundation

enum AboutAcknowledgements {
    struct RuntimeLibrary: Equatable {
        let name: String
        let url: URL
        let licenseURL: URL
    }

    struct AssetCredit: Equatable {
        let name: String
        let url: URL
    }

    static let projectURL = URL(string: "https://github.com/victorhqc/filbert")!
    static let licenseURL = URL(string: "https://github.com/victorhqc/filbert/blob/main/LICENSE")!
    static let runtimeLibraries = [
        RuntimeLibrary(
            name: "Sparkle",
            url: URL(string: "https://sparkle-project.org")!,
            licenseURL: URL(string: "https://github.com/sparkle-project/Sparkle/blob/2.9.1/LICENSE")!
        ),
    ]
    static let assetCredits = [
        AssetCredit(
            name: "Simple Icons",
            url: URL(string: "https://github.com/simple-icons/simple-icons")!
        ),
    ]
}
