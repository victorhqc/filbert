import Core
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexRefreshCharacteristicsTests: XCTestCase {
    func testProvider_declaresUnknownCostWithoutAnInferenceCap() {
        XCTAssertEqual(
            OpenAICodexProvider.refreshCharacteristics,
            ProviderRefreshCharacteristics(
                costEvidence: .unknown,
                canInvokeInference: false
            )
        )
    }
}
