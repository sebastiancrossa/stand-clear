import Foundation

func message(_ fields: [[UInt8]]) -> [UInt8] {
    fields.flatMap { $0 }
}

func stringField(_ number: UInt64, _ value: String) -> [UInt8] {
    lengthDelimitedField(number, Array(value.utf8))
}

func messageField(_ number: UInt64, _ value: [UInt8]) -> [UInt8] {
    lengthDelimitedField(number, value)
}

func lengthDelimitedField(_ number: UInt64, _ value: [UInt8]) -> [UInt8] {
    varint((number << 3) | 2) + varint(UInt64(value.count)) + value
}

func varintField(_ number: UInt64, _ value: UInt64) -> [UInt8] {
    varint(number << 3) + varint(value)
}

func varint(_ value: UInt64) -> [UInt8] {
    var value = value
    var bytes: [UInt8] = []
    repeat {
        var byte = UInt8(value & 0x7f)
        value >>= 7
        if value != 0 { byte |= 0x80 }
        bytes.append(byte)
    } while value != 0
    return bytes
}

/// Serves canned responses by URL. Shared by the trip feed and service alert clients.
final class MockURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let data: Data
    }

    static var responses: [URL: Response] = [:]

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
