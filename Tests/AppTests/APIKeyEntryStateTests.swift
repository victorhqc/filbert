@testable import App
import XCTest

final class APIKeyEntryStateTests: XCTestCase {
    func testFailedSaveRetainsInputAndShowsAnError() {
        var state = APIKeyEntryState()
        state.updateInput("example-key")

        state.save { _ in
            throw APIKeyEntryTestError.failed
        }

        XCTAssertEqual(state.input, "example-key")
        XCTAssertNotNil(state.errorMessage)
    }

    func testSuccessfulRetryClearsInputAndError() {
        var state = APIKeyEntryState()
        state.updateInput("example-key")
        state.save { _ in throw APIKeyEntryTestError.failed }

        state.save { key in
            XCTAssertEqual(key, "example-key")
        }

        XCTAssertEqual(state.input, "")
        XCTAssertNil(state.errorMessage)
    }

    func testChangingInputClearsPreviousError() {
        var state = APIKeyEntryState()
        state.updateInput("example-key")
        state.save { _ in throw APIKeyEntryTestError.failed }

        state.updateInput("updated-example-key")

        XCTAssertNil(state.errorMessage)
    }

    func testFailedClearShowsAnError() {
        var state = APIKeyEntryState()

        state.clear {
            throw APIKeyEntryTestError.failed
        }

        XCTAssertNotNil(state.errorMessage)
    }
}

private enum APIKeyEntryTestError: Error {
    case failed
}
