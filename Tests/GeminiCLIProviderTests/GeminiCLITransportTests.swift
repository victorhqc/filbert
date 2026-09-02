import Foundation
@testable import GeminiCLIProvider
import XCTest

extension GeminiCLIProviderTests {
    func testURLSessionTransportRejectsUnexpectedFinalHost() async throws {
        GeminiHostResponseURLProtocol.responseURL = try XCTUnwrap(URL(string: "https://example.com"))
        GeminiHostResponseURLProtocol.responseData = Data()
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
        defer {
            GeminiHostResponseURLProtocol.responseStatusCode = 200
            GeminiHostResponseURLProtocol.responseHeaders = nil
        }

        do {
            _ = try await transport.send(request)
            XCTFail("Expected unexpected-host error")
        } catch let error as GeminiHTTPError {
            XCTAssertEqual(error, .network)
        }
    }

    func testURLSessionTransportLogsOnlyStatusAndLatency() async throws {
        let responseURL = try XCTUnwrap(
            URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
        )
        GeminiHostResponseURLProtocol.responseURL = responseURL
        GeminiHostResponseURLProtocol.responseData = Data(
            #"{"project":"project-secret","token":"access-secret"}"#.utf8
        )
        defer {
            GeminiHostResponseURLProtocol.responseURL = nil
            GeminiHostResponseURLProtocol.responseData = Data()
            GeminiHostResponseURLProtocol.responseStatusCode = 200
            GeminiHostResponseURLProtocol.responseHeaders = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiHostResponseURLProtocol.self]
        let logger = RecordingLogSink()
        let transport = URLSessionGeminiHTTPTransport(
            session: URLSession(configuration: configuration),
            logger: logger
        )

        _ = try await transport.send(URLRequest(url: responseURL))

        let entries = logger.recordedEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].contains("status=200"))
        XCTAssertFalse(entries.joined().contains("project-secret"))
        XCTAssertFalse(entries.joined().contains("access-secret"))
    }

    func testURLSessionTransportParsesRetryAfterHeader() async throws {
        let responseURL = try XCTUnwrap(
            URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
        )
        GeminiHostResponseURLProtocol.responseURL = responseURL
        GeminiHostResponseURLProtocol.responseStatusCode = 429
        GeminiHostResponseURLProtocol.responseHeaders = ["Retry-After": "2"]
        defer {
            GeminiHostResponseURLProtocol.responseURL = nil
            GeminiHostResponseURLProtocol.responseData = Data()
            GeminiHostResponseURLProtocol.responseStatusCode = 200
            GeminiHostResponseURLProtocol.responseHeaders = nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiHostResponseURLProtocol.self]
        let transport = URLSessionGeminiHTTPTransport(
            session: URLSession(configuration: configuration)
        )

        let response = try await transport.send(URLRequest(url: responseURL))

        XCTAssertEqual(response.statusCode, 429)
        XCTAssertEqual(response.retryAfter, 2)
    }

    func testRedirectDelegateRejectsRedirects() throws {
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        let task = try session.dataTask(
            with: XCTUnwrap(URL(string: "https://cloudcode-pa.googleapis.com"))
        )
        let response = try XCTUnwrap(
            try HTTPURLResponse(
                url: XCTUnwrap(URL(string: "https://cloudcode-pa.googleapis.com")),
                statusCode: 302,
                httpVersion: nil,
                headerFields: nil
            )
        )
        var redirectedRequest: URLRequest?

        try GeminiRedirectDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: XCTUnwrap(response.url)),
            completionHandler: { redirectedRequest = $0 }
        )

        XCTAssertNil(redirectedRequest)
        task.cancel()
        session.invalidateAndCancel()
    }
}
