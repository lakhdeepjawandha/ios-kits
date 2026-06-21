import Foundation

/// Async REST client abstraction. Conform a mock (see ``MockAPIClient``) for offline tests, or use
/// ``LiveAPIClient`` against a real `URLSession`.
public protocol APIClient: Sendable {
    /// Send a ``Request`` and decode the JSON response into `T`.
    ///
    /// - Parameter request: The endpoint description to send.
    /// - Returns: The decoded value.
    /// - Throws: ``APIError`` for transport, status, or decoding failures.
    func send<T: Decodable>(_ request: Request) async throws -> T

    /// Convenience `GET` of an absolute `URL`, decoding the JSON response into `T`.
    ///
    /// - Parameters:
    ///   - url: The absolute URL to fetch.
    ///   - type: The type to decode.
    /// - Returns: The decoded value.
    /// - Throws: ``APIError`` for transport, status, or decoding failures.
    func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T
}

extension APIClient {
    /// Default `GET` implementation expressed in terms of ``send(_:)``.
    public func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        try await send(Request.get(url.absoluteString))
    }
}

/// `URLSession`-backed ``APIClient`` with typed errors and built-in retry/backoff.
///
/// Configure it with an optional `baseURL` (so requests can use relative paths), JSON coders, and a
/// ``RetryPolicy``. Each ``send(_:)`` validates the HTTP status, maps failures to ``APIError``, and
/// retries transient failures according to the policy.
///
/// ```swift
/// let client = LiveAPIClient(baseURL: URL(string: "https://api.example.com")!)
/// let quote: Quote = try await client.send(.get("v1/quotes").adding(query: "symbol", "BTC"))
/// ```
public struct LiveAPIClient: APIClient {
    let session: URLSession
    let baseURL: URL?
    let decoder: JSONDecoder
    let encoder: JSONEncoder
    let retryPolicy: RetryPolicy
    let sleeper: Sleeper

    /// Create a live client.
    ///
    /// - Parameters:
    ///   - session: The `URLSession` to use. Defaults to `.shared`.
    ///   - baseURL: Optional base URL for resolving relative request paths.
    ///   - decoder: JSON decoder for responses. Defaults to a fresh `JSONDecoder`.
    ///   - encoder: JSON encoder for request bodies. Defaults to a fresh `JSONEncoder`.
    ///   - retryPolicy: Retry behaviour for transient failures. Defaults to ``RetryPolicy/default``.
    public init(session: URLSession = .shared,
                baseURL: URL? = nil,
                decoder: JSONDecoder = JSONDecoder(),
                encoder: JSONEncoder = JSONEncoder(),
                retryPolicy: RetryPolicy = .default) {
        self.init(session: session,
                  baseURL: baseURL,
                  decoder: decoder,
                  encoder: encoder,
                  retryPolicy: retryPolicy,
                  sleeper: liveSleeper)
    }

    /// Designated initializer with an injectable `sleeper`, used by tests to avoid real waiting.
    init(session: URLSession = .shared,
         baseURL: URL? = nil,
         decoder: JSONDecoder = JSONDecoder(),
         encoder: JSONEncoder = JSONEncoder(),
         retryPolicy: RetryPolicy = .default,
         sleeper: @escaping Sleeper) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = decoder
        self.encoder = encoder
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    public func send<T: Decodable>(_ request: Request) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await perform(request)
            } catch let error as APIError {
                guard attempt < retryPolicy.maxRetries, retryPolicy.isRetryable(error) else {
                    throw error
                }
                try await sleeper(retryPolicy.delay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    /// One round-trip: build the URLRequest, fetch, validate status, decode. Maps every failure to
    /// an ``APIError`` so ``send(_:)`` can apply the retry policy uniformly.
    private func perform<T: Decodable>(_ request: Request) async throws -> T {
        let urlRequest = try request.urlRequest(baseURL: baseURL)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw APIError.transport(urlError)
        } catch {
            throw APIError.unknown(message: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(message: "Response was not an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.unacceptableStatus(code: http.statusCode, body: data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(message: String(describing: error))
        }
    }
}
