import Foundation

/// URLProtocol subclass that routes requests through a configurable handler,
/// supporting per-endpoint responses (refresh vs. usage) in a single test
/// session.
final class MockURLProtocol: URLProtocol {
    struct MockResponse {
        let data: Data
        let statusCode: Int
        let error: Error?
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> MockResponse)?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // URLSession may convert httpBody to a body stream before the
        // URLProtocol sees it. Materialize it so tests can assert on it.
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let bodyStream = capturedRequest.httpBodyStream {
            capturedRequest.httpBody = readBody(from: bodyStream)
        }
        Self.lastRequest = capturedRequest

        let mock = handler(capturedRequest)

        if let error = mock.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: mock.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func readBody(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            }
        }
        return data
    }
}
