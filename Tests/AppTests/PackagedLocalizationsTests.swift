@testable import App
import Foundation
import XCTest

final class PackagedLocalizationsTests: XCTestCase {
    func testThePackagedAppDeclaresEverySupportedLanguage() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../packaging/Info.plist")
            .standardizedFileURL
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let localizations = try XCTUnwrap((plist as? [String: Any])?["CFBundleLocalizations"] as? [String])

        XCTAssertEqual(localizations, SupportedLanguage.all.map(\.code))
    }
}
