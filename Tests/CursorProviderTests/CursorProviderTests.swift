import Core
@testable import CursorProvider
import Foundation
import XCTest

final class CursorProviderTests: XCTestCase {
    // MARK: - AC1: provider-owned glyph (providers 07)

    func testProviderGlyphLoadsFromModuleResources() {
        guard case let .asset(name, bundle) = CursorProvider.providerGlyph else {
            return XCTFail("Expected an asset-backed provider glyph")
        }

        XCTAssertEqual(name, "ProviderGlyph")
        XCTAssertNotNil(bundle.url(forResource: name, withExtension: "png"))
        XCTAssertNotNil(bundle.url(forResource: "\(name)@2x", withExtension: "png"))
    }

    // MARK: - AC2b: external login prerequisite (providers 07)

    func testSetupHelpPointsToCursorCLIAuthenticationDocs() {
        XCTAssertEqual(CursorProvider.setupHelp.linkLabel, "Sign in to Cursor")
        XCTAssertEqual(
            CursorProvider.setupHelp.url,
            URL(string: "https://docs.cursor.com/en/cli/reference/authentication")
        )
    }
}
