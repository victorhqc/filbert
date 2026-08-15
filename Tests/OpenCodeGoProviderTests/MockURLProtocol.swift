import Foundation

final class MockURLProtocol: URLProtocol {
    static var responseData = Data()
    static var responseStatusCode = 200
    static var responseError: Error?
    static var lastRequest: URLRequest?
    static var requestCount = 0

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.requestCount += 1

        if let responseError = Self.responseError {
            client?.urlProtocol(self, didFailWithError: responseError)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
