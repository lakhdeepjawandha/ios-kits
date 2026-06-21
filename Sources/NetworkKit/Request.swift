import Foundation

/// HTTP methods supported by ``Request``.
public enum HTTPMethod: String, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

/// A declarative description of an HTTP endpoint — method, path, query, headers, and body.
///
/// `Request` is a value type with a small builder API so call sites read top-to-bottom:
///
/// ```swift
/// let request = Request.get("v1/quotes")
///     .adding(query: "symbol", "BTC")
///     .setting(header: "Accept", to: "application/json")
///
/// let quote: Quote = try await client.send(request)
/// ```
///
/// The `path` may be **relative** (resolved against the client's `baseURL`) or an **absolute**
/// URL string (e.g. `"https://api.example.com/v1/quotes"`), in which case any `baseURL` is ignored.
/// Resolve it to a `URLRequest` with ``urlRequest(baseURL:)``.
public struct Request: Sendable, Equatable {
    /// The HTTP method. Defaults to `.get`.
    public var method: HTTPMethod
    /// Relative path (joined onto the client `baseURL`) or an absolute URL string.
    public var path: String
    /// Query items appended to the resolved URL.
    public var query: [URLQueryItem]
    /// HTTP header fields applied to the request.
    public var headers: [String: String]
    /// Raw request body bytes, if any.
    public var body: Data?

    /// Create a request. Prefer the static helpers (``get(_:)``, ``post(_:)``, …) for brevity.
    ///
    /// - Parameters:
    ///   - method: HTTP method. Defaults to `.get`.
    ///   - path: Relative path or absolute URL string.
    ///   - query: Query items. Defaults to empty.
    ///   - headers: Header fields. Defaults to empty.
    ///   - body: Raw body bytes. Defaults to `nil`.
    public init(method: HTTPMethod = .get,
                path: String,
                query: [URLQueryItem] = [],
                headers: [String: String] = [:],
                body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    // MARK: - Method factories

    /// A `GET` request for the given path.
    public static func get(_ path: String) -> Request { Request(method: .get, path: path) }
    /// A `POST` request for the given path.
    public static func post(_ path: String) -> Request { Request(method: .post, path: path) }
    /// A `PUT` request for the given path.
    public static func put(_ path: String) -> Request { Request(method: .put, path: path) }
    /// A `PATCH` request for the given path.
    public static func patch(_ path: String) -> Request { Request(method: .patch, path: path) }
    /// A `DELETE` request for the given path.
    public static func delete(_ path: String) -> Request { Request(method: .delete, path: path) }

    // MARK: - Builder helpers (return a modified copy)

    /// Returns a copy with a header field set (replacing any existing value for that name).
    public func setting(header name: String, to value: String) -> Request {
        var copy = self
        copy.headers[name] = value
        return copy
    }

    /// Returns a copy with the given header fields merged in (new values win).
    public func setting(headers newHeaders: [String: String]) -> Request {
        var copy = self
        copy.headers.merge(newHeaders) { _, new in new }
        return copy
    }

    /// Returns a copy with one query item appended.
    public func adding(query name: String, _ value: String) -> Request {
        var copy = self
        copy.query.append(URLQueryItem(name: name, value: value))
        return copy
    }

    /// Returns a copy with multiple query items appended.
    public func adding(queryItems items: [URLQueryItem]) -> Request {
        var copy = self
        copy.query.append(contentsOf: items)
        return copy
    }

    /// Returns a copy with the given raw body bytes.
    public func with(body data: Data) -> Request {
        var copy = self
        copy.body = data
        return copy
    }

    /// Returns a copy whose body is `value` encoded as JSON, with `Content-Type: application/json`.
    ///
    /// - Parameters:
    ///   - value: The `Encodable` value to serialize.
    ///   - encoder: The encoder to use. Defaults to a fresh `JSONEncoder`.
    /// - Throws: ``APIError/encoding(message:)`` if encoding fails.
    public func jsonBody<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Request {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw APIError.encoding(message: String(describing: error))
        }
        return with(body: data).setting(header: "Content-Type", to: "application/json")
    }

    // MARK: - Resolution

    /// Resolve this request into a `URLRequest`.
    ///
    /// If ``path`` is an absolute URL string (has a scheme), `baseURL` is ignored. Otherwise the
    /// path is appended to `baseURL`. Query items are appended to whatever query the resolved URL
    /// already has.
    ///
    /// - Parameter baseURL: The base URL for relative paths. May be `nil` when ``path`` is absolute.
    /// - Returns: A configured `URLRequest`.
    /// - Throws: ``APIError/invalidURL`` if a valid URL cannot be formed.
    public func urlRequest(baseURL: URL? = nil) throws -> URLRequest {
        let resolved: URL
        let pathHasScheme = URLComponents(string: path)?.scheme != nil

        if let baseURL, !pathHasScheme {
            let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
            resolved = trimmed.isEmpty ? baseURL : baseURL.appendingPathComponent(trimmed)
        } else {
            guard let url = URL(string: path) else { throw APIError.invalidURL }
            resolved = url
        }

        guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let finalURL = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        return request
    }
}
