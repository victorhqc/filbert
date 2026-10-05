import Core
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexRefreshCharacteristicsTests: XCTestCase {
    func testProvider_declaresUnknownCostAndInferenceCapability() {
        XCTAssertEqual(
            OpenAICodexProvider.refreshCharacteristics,
            ProviderRefreshCharacteristics(
                costEvidence: .unknown,
                canInvokeInference: true
            )
        )
    }
}
