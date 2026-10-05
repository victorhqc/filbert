import Core
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexRefreshCharacteristicsTests: XCTestCase {
    func testProvider_declaresPossibleConsumptionAndInferenceCapability() {
        XCTAssertEqual(
            OpenAICodexProvider.refreshCharacteristics,
            ProviderRefreshCharacteristics(
                costEvidence: .possibleConsumption,
                canInvokeInference: true
            )
        )
    }
}
