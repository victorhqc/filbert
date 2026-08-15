@testable import App
import XCTest

final class AppVersionTests: XCTestCase {
    func testPresentationUsesShortVersion() {
        let presentation = AppVersion.presentation(shortVersion: "0.9.0")

        XCTAssertEqual(presentation, "filbert v0.9.0")
    }

    func testPresentationNormalizesOneLeadingVersionPrefix() {
        let presentation = AppVersion.presentation(shortVersion: "v0.9.0")

        XCTAssertEqual(presentation, "filbert v0.9.0")
    }

    func testPresentationUsesDevelopmentFallbackForMissingVersion() {
        XCTAssertEqual(AppVersion.presentation(shortVersion: nil), "filbert development")
    }

    func testPresentationUsesDevelopmentFallbackForBlankVersion() {
        let presentation = AppVersion.presentation(shortVersion: "   ")

        XCTAssertEqual(presentation, "filbert development")
    }

    func testPresentationUsesDevelopmentFallbackForBuildPlaceholder() {
        let presentation = AppVersion.presentation(shortVersion: "@VERSION@")

        XCTAssertEqual(presentation, "filbert development")
    }

    func testPresentationUsesDevelopmentFallbackForZeroVersion() {
        let presentation = AppVersion.presentation(shortVersion: "0.0.0")

        XCTAssertEqual(presentation, "filbert development")
    }
}
