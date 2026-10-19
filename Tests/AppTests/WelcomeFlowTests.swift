@testable import App
import XCTest

@MainActor
final class WelcomeFlowTests: XCTestCase {
    func testStepsMoveForwardAndBackWithinBounds() {
        let flow = WelcomeFlow()

        flow.goBack()
        XCTAssertEqual(flow.step, .introduction)
        XCTAssertTrue(flow.isFirstStep)

        flow.goForward()
        flow.goForward()
        flow.goForward()
        XCTAssertEqual(flow.step, .menuBar)
        XCTAssertTrue(flow.isLastStep)
        XCTAssertEqual(flow.step.number, WelcomeStep.allCases.count)

        flow.goBack()
        XCTAssertEqual(flow.step, .provider)
    }

    func testRestartReturnsToTheFirstStepAndClearsTheSelection() {
        let flow = WelcomeFlow()
        flow.goForward()
        flow.selectedProviderId = "provider"

        flow.restart()

        XCTAssertEqual(flow.step, .introduction)
        XCTAssertNil(flow.selectedProviderId)
    }
}
