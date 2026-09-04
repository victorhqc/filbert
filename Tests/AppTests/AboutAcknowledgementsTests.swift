@testable import App
import XCTest

final class AboutAcknowledgementsTests: XCTestCase {
    func testRuntimeLibrariesIncludeSparkle() {
        XCTAssertTrue(
            AboutAcknowledgements.runtimeLibraries.contains {
                $0.name == "Sparkle"
                    && $0.url.absoluteString == "https://sparkle-project.org"
                    && $0.licenseURL.absoluteString
                    == "https://github.com/sparkle-project/Sparkle/blob/2.9.1/LICENSE"
            }
        )
    }

    func testProjectAndLicenseURLsAreCanonical() {
        XCTAssertEqual(
            AboutAcknowledgements.projectURL.absoluteString,
            "https://github.com/victorhqc/filbert"
        )
        XCTAssertEqual(
            AboutAcknowledgements.licenseURL.absoluteString,
            "https://github.com/victorhqc/filbert/blob/main/LICENSE"
        )
    }

    func testAssetCreditsIncludeSimpleIcons() {
        XCTAssertTrue(
            AboutAcknowledgements.assetCredits.contains {
                $0.name == "Simple Icons"
                    && $0.url.absoluteString == "https://github.com/simple-icons/simple-icons"
            }
        )
    }

    func testMascotLoadsFromTheAppResourceBundle() {
        XCTAssertNotNil(AboutMascot.load())
    }
}
