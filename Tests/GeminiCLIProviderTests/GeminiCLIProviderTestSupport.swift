import Core
import Foundation
@testable import GeminiCLIProvider
import XCTest

extension GeminiCLIProviderTests {
    func validCredentials() -> GeminiCredentials {
        GeminiCredentials(
            accessToken: "access-token",
            refreshToken: nil,
            expiresAt: Date(timeIntervalSince1970: 10000)
        )
    }

    func makeProvider(
        credentials: GeminiCredentials?,
        transport: RecordingTransport = RecordingTransport(responses: []),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
    ) -> GeminiCLIProvider {
        makeProvider(
            credentialsResult: .success(credentials),
            transport: transport,
            now: now
        )
    }

    func makeProvider(
        credentialsResult: Result<GeminiCredentials?, GeminiCredentialError>,
        transport: RecordingTransport = RecordingTransport(responses: []),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
    ) -> GeminiCLIProvider {
        let http = GeminiHTTPClient(transport: transport, sleep: { _ in })
        return GeminiCLIProvider(
            credentialStore: StubCredentialStore(result: credentialsResult),
            oauth: GeminiOAuthClient(http: http),
            codeAssist: GeminiCodeAssistClient(
                http: http,
                environment: [:]
            ),
            now: now
        )
    }

    func decodeFixture<T: Decodable>(
        _ name: String,
        as _: T.Type
    ) throws -> T {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name.replacingOccurrences(of: ".json", with: ""),
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

private struct StubCredentialStore: GeminiCredentialStore {
    let result: Result<GeminiCredentials?, GeminiCredentialError>

    func load() throws -> GeminiCredentials? {
        try result.get()
    }
}

actor RecordingTransport: GeminiHTTPTransport {
    private var remainingResponses: [GeminiHTTPResponse]
    private var requests: [URLRequest] = []
    private let delay: TimeInterval

    init(responses: [GeminiHTTPResponse], delay: TimeInterval = 0) {
        remainingResponses = responses
        self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> GeminiHTTPResponse {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        requests.append(request)
        guard !remainingResponses.isEmpty else {
            throw GeminiHTTPError.network
        }
        return remainingResponses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

class GeminiHostResponseURLProtocol: URLProtocol {
    static var responseURL: URL?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseURL = Self.responseURL,
              let response = HTTPURLResponse(
                  url: responseURL,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: nil
              )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: GeminiHTTPError.network
            )
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
