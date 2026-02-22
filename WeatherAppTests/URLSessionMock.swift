import Foundation

extension URLSession {
    static func mockSession(forecastJSON: Data, marineJSON: Data) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.forecastData = forecastJSON
        MockURLProtocol.marineData   = marineJSON
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var forecastData: Data = Data()
    nonisolated(unsafe) static var marineData:   Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = request.url?.host?.contains("marine") == true
            ? MockURLProtocol.marineData
            : MockURLProtocol.forecastData
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
