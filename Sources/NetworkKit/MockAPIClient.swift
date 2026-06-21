import Foundation

/// A canned HTTP response for ``StubURLProtocol`` to return.
public struct StubResponse: Sendable {
    /// HTTP status code to report. Defaults to `200`.
    public var statusCode: Int
    /// Response body bytes, if any.
    public var body: Data?
    /// Response header fields.
    public var headers: [String: String]

    /// Create a stub response.
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status code. Default `200`.
    ///   - body: Response body. Default `nil`.
    ///   - headers: Response headers. Default empty.
    public init(statusCode: Int = 200, body: Data? = nil, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    /// A JSON response with the given body and status, tagged `Content-Type: application/json`.
    public static func json(_ body: Data, status: Int = 200) -> StubResponse {
        StubResponse(statusCode: status, body: body, headers: ["Content-Type": "application/json"])
    }
}

/// A `URLProtocol` that intercepts every request and answers from an installed handler, so tests
/// run fully offline.
///
/// Install a handler with ``setHandler(_:)`` (or via ``MockAPIClient``'s `stub` helpers). The
/// handler may return a ``StubResponse`` or `throw` a `URLError` to simulate a transport failure.
///
/// - Important: The handler is process-global static state. `XCTest` runs the tests within a class
///   serially, so set the handler in each test and clear it in `tearDown` (see
///   ``MockAPIClient/reset()``) to avoid cross-test bleed.
public final class StubURLProtocol: URLProtocol {

    /// A handler that turns an outgoing request into a stubbed response (or throws to fail it).
    public typealias Handler = @Sendable (URLRequest) throws -> StubResponse

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?

    /// Install (or clear, by passing `nil`) the global request handler.
    public static func setHandler(_ handler: Handler?) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
    }

    private static var handler: Handler? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let stub = try handler(request)
            let url = request.url ?? URL(string: "about:blank")!
            let response = HTTPURLResponse(url: url,
                                           statusCode: stub.statusCode,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let body = stub.body {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}

/// An ``APIClient`` wired to a ``StubURLProtocol`` so tests and SwiftUI previews never hit the
/// network.
///
/// Under the hood it is a ``LiveAPIClient`` on an ephemeral `URLSession` whose only protocol is the
/// stub — so it exercises the same status-validation, decoding, and (optionally) retry code paths
/// as production, just against canned responses.
///
/// ```swift
/// let client = MockAPIClient(baseURL: URL(string: "https://api.example.com")!)
/// client.stub(json: try Fixture.data("quote", in: .module))
/// let quote: Quote = try await client.send(.get("v1/quotes"))
/// MockAPIClient.reset()   // in tearDown
/// ```
public struct MockAPIClient: APIClient {
    private let client: LiveAPIClient

    /// Create a mock client.
    ///
    /// - Parameters:
    ///   - baseURL: Optional base URL for resolving relative request paths.
    ///   - decoder: JSON decoder for responses. Defaults to a fresh `JSONDecoder`.
    ///   - encoder: JSON encoder for request bodies. Defaults to a fresh `JSONEncoder`.
    ///   - retryPolicy: Retry behaviour. Defaults to ``RetryPolicy/none`` so tests are deterministic.
    public init(baseURL: URL? = nil,
                decoder: JSONDecoder = JSONDecoder(),
                encoder: JSONEncoder = JSONEncoder(),
                retryPolicy: RetryPolicy = .none) {
        self.client = LiveAPIClient(session: Self.makeSession(),
                                    baseURL: baseURL,
                                    decoder: decoder,
                                    encoder: encoder,
                                    retryPolicy: retryPolicy)
    }

    /// Build an ephemeral `URLSession` whose only protocol is ``StubURLProtocol``.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    public func send<T: Decodable>(_ request: Request) async throws -> T {
        try await client.send(request)
    }

    public func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        try await client.get(url, as: type)
    }

    // MARK: - Stubbing

    /// Install a custom handler that maps each outgoing request to a ``StubResponse`` (or throws).
    public func stub(_ handler: @escaping StubURLProtocol.Handler) {
        StubURLProtocol.setHandler(handler)
    }

    /// Answer every request with the given JSON body and status code.
    public func stub(json body: Data, status: Int = 200) {
        StubURLProtocol.setHandler { _ in .json(body, status: status) }
    }

    /// Answer every request with the given status code and optional body.
    public func stub(status: Int, body: Data? = nil) {
        StubURLProtocol.setHandler { _ in StubResponse(statusCode: status, body: body) }
    }

    /// Fail every request with the given `URLError`, simulating a transport failure.
    public func stub(transportError code: URLError.Code) {
        StubURLProtocol.setHandler { _ in throw URLError(code) }
    }

    /// Clear any installed stub handler. Call from `tearDown`.
    public static func reset() {
        StubURLProtocol.setHandler(nil)
    }
}

/// Loads JSON fixtures bundled with a target — handy for tests and SwiftUI previews.
///
/// Place `.json` files in a resource directory (e.g. `Tests/.../Fixtures`) and load them via
/// `Bundle.module`:
///
/// ```swift
/// let quote: Quote = try Fixture.decode(Quote.self, from: "quote", in: .module)
/// ```
public enum Fixture {
    /// Read the raw bytes of a bundled resource.
    ///
    /// - Parameters:
    ///   - name: Resource file name without extension.
    ///   - ext: File extension. Default `"json"`.
    ///   - bundle: Bundle containing the resource (pass `.module` from the owning target).
    /// - Returns: The file contents.
    /// - Throws: ``APIError/fixtureNotFound(name:)`` if the resource is missing.
    public static func data(_ name: String, withExtension ext: String = "json", in bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw APIError.fixtureNotFound(name: "\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }

    /// Read and JSON-decode a bundled resource into `T`.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - name: Resource file name without extension.
    ///   - ext: File extension. Default `"json"`.
    ///   - bundle: Bundle containing the resource (pass `.module`).
    ///   - decoder: Decoder to use. Defaults to a fresh `JSONDecoder`.
    /// - Returns: The decoded value.
    /// - Throws: ``APIError/fixtureNotFound(name:)`` if missing, or ``APIError/decoding(message:)``
    ///   if decoding fails.
    public static func decode<T: Decodable>(_ type: T.Type,
                                            from name: String,
                                            withExtension ext: String = "json",
                                            in bundle: Bundle,
                                            decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let data = try data(name, withExtension: ext, in: bundle)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(message: String(describing: error))
        }
    }
}
