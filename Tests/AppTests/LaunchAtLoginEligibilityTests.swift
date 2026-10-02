@testable import App
import Foundation
import XCTest

final class LaunchAtLoginEligibilityTests: XCTestCase {
    func testBareExecutableIsNotEligible() {
        XCTAssertFalse(LaunchAtLoginEligibility.isEligible(bundle: .main))
    }

    func testAppBundleIsEligible() throws {
        let bundle = try makeBundle()

        XCTAssertTrue(LaunchAtLoginEligibility.isEligible(bundle: bundle))
    }

    func testNonAppBundleIsNotEligible() throws {
        let bundle = try makeBundle(pathExtension: "bundle")

        XCTAssertFalse(LaunchAtLoginEligibility.isEligible(bundle: bundle))
    }

    func testWrongPackageTypeIsNotEligible() throws {
        let bundle = try makeBundle(packageType: "BNDL")

        XCTAssertFalse(LaunchAtLoginEligibility.isEligible(bundle: bundle))
    }

    func testMissingOrEmptyIdentifierIsNotEligible() throws {
        for identifier in [nil, ""] {
            let bundle = try makeBundle(identifier: identifier)

            XCTAssertFalse(LaunchAtLoginEligibility.isEligible(bundle: bundle))
        }
    }

    private func makeBundle(
        pathExtension: String = "app",
        packageType: String = "APPL",
        identifier: String? = "com.victorhqc.filbert.tests"
    ) throws -> Bundle {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleURL = rootURL.appendingPathComponent("Filbert.\(pathExtension)")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        var info = ["CFBundlePackageType": packageType]
        info["CFBundleIdentifier"] = identifier
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        try (info as NSDictionary).write(to: infoURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
