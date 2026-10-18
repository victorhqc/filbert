import Core
import XCTest

/// The assertions compare English text, and the test Mac may run in another language.
class EnglishTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        super.tearDown()
    }
}
