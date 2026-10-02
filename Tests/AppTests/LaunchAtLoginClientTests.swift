@testable import App
import Foundation
import ServiceManagement
import XCTest

final class LaunchAtLoginClientTests: XCTestCase {
    func testNotRegisteredStatusIsPreserved() {
        XCTAssertEqual(LaunchAtLoginStatus(nativeStatus: .notRegistered), .notRegistered)
    }

    func testEnabledStatusIsPreserved() {
        XCTAssertEqual(LaunchAtLoginStatus(nativeStatus: .enabled), .enabled)
    }

    func testApprovalRequiredStatusIsPreserved() {
        XCTAssertEqual(LaunchAtLoginStatus(nativeStatus: .requiresApproval), .requiresApproval)
    }

    func testMissingNativeServiceIsNotAnUnavailableApp() {
        XCTAssertEqual(LaunchAtLoginStatus(nativeStatus: .notFound), .notFound)
        XCTAssertNotEqual(LaunchAtLoginStatus(nativeStatus: .notFound), .unavailable)
    }

    func testUnknownNativeStatusIsUnavailable() throws {
        let nativeStatus = try XCTUnwrap(SMAppService.Status(rawValue: Int.max))

        XCTAssertEqual(LaunchAtLoginStatus(nativeStatus: nativeStatus), .unavailable)
    }

    @MainActor
    func testBareExecutableCannotMakeNativeRegistrationRequests() throws {
        try XCTSkipIf(
            LaunchAtLoginEligibility.isEligible(bundle: .main),
            "An eligible test host could change the user's login items."
        )
        let client = SystemLaunchAtLoginClient()

        XCTAssertEqual(client.status, .unavailable)
        XCTAssertThrowsError(try client.register())
        XCTAssertThrowsError(try client.unregister())
    }
}
