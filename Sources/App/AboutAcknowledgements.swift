import Foundation

enum AboutAcknowledgements {
    struct RuntimeLibrary: Equatable {
        let name: String
        let url: URL
    }

    struct AssetCredit: Equatable {
        let name: String
        let url: URL
    }

    static let projectURL = URL(string: "https://github.com/victorhqc/filbert")!
    static let licenseURL = URL(string: "https://github.com/victorhqc/filbert/blob/main/LICENSE")!
    static let runtimeLibraries: [RuntimeLibrary] = []
    static let assetCredits = [
        AssetCredit(
            name: "Simple Icons",
            url: URL(string: "https://github.com/simple-icons/simple-icons")!
        ),
    ]
}
