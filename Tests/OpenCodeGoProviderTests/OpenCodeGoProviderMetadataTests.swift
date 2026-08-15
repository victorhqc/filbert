import Core
import Foundation
@testable import OpenCodeGoProvider
import XCTest

final class OpenCodeGoProviderMetadataTests: XCTestCase {
    func testProviderGlyphLoadsFromModuleResources() {
        guard case let .asset(name, bundle) = OpenCodeGoProvider.providerGlyph else {
            return XCTFail("Expected an asset-backed provider glyph")
        }

        XCTAssertEqual(name, "ProviderGlyph")
        XCTAssertNotNil(bundle.url(forResource: name, withExtension: "png"))
        XCTAssertNotNil(bundle.url(forResource: "\(name)@2x", withExtension: "png"))
    }
}
