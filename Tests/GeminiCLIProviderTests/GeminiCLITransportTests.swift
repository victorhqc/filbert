import Foundation
@testable import GeminiCLIProvider
import XCTest

extension GeminiCLIProviderTests {
    func testURLSessionTransportRejectsUnexpectedFinalHost() async throws {
        GeminiHostResponseURLProtocol.responseURL = try XCTUnwrap(URL(string: "https://example.com"))
        defer { GeminiHostResponseURLProtocol.responseURL = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiHostResponseURLProtocol.self]
        let transport = URLSessionGeminiHTTPTransport(
            session: URLSession(configuration: configuration)
        )
        let requestURL = try XCTUnwrap(
            URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
        )
        let request = URLRequest(url: requestURL)

        do {
            _ = try await transport.send(request)
            XCTFail("Expected unexpected-host error")
        } catch let error as GeminiHTTPError {
            XCTAssertEqual(error, .network)
        }
    }
}
