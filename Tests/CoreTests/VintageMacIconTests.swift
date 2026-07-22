import Core
import XCTest

final class VintageMacIconTests: XCTestCase {
    private let suiteName = "ai-usage.tests.vintage-mac-icon"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        VintageMacIcon.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        VintageMacIcon.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testIsEnabled_returnsFalseWhenUnset() {
        XCTAssertFalse(VintageMacIcon.isEnabled)
    }

    func testSetEnabled_persistsAndReadsBack() {
        VintageMacIcon.setEnabled(true)

        XCTAssertTrue(VintageMacIcon.isEnabled)
    }

    func testSetEnabled_survivesUserDefaultsSwap() throws {
        VintageMacIcon.setEnabled(true)

        let resurrected = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        VintageMacIcon.setUserDefaults(resurrected)

        XCTAssertTrue(VintageMacIcon.isEnabled)
    }

    func testIsEnabled_returnsFalseForInvalidStoredValue() {
        defaults.set("enabled", forKey: "vintage-mac-icon-enabled")

        XCTAssertFalse(VintageMacIcon.isEnabled)
    }
}
