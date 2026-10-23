import Foundation

/// Mock URLProtocol shared by tests in this module. Not `private` so the
/// test classes can stay under SwiftLint's type-body-length threshold.
final class MockURLProtocol: URLProtocol {
    static var responseData: Data?
    static var responseStatusCode = 200
    static var responseHeaders: [String: String]?
    static var responseError: Error?
    static var lastRequest: URLRequest?

    static func reset() {
        responseData = nil
        responseStatusCode = 200
        responseHeaders = nil
        responseError = nil
        lastRequest = nil
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        MockURLProtocol.lastRequest = request

        if let error = MockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: nil,
            headerFields: MockURLProtocol.responseHeaders
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
