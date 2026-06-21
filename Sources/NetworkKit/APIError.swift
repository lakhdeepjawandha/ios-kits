import Foundation

/// Typed errors surfaced by ``APIClient`` requests.
///
/// Every failure mode of a request maps to exactly one case, so callers can switch on the cause —
/// transport vs. server status vs. decoding — instead of inspecting opaque `NSError`s. Used by the
/// retry machinery (see ``RetryPolicy``) to decide which failures are worth retrying.
public enum APIError: Error, Equatable {
    /// The request could not be turned into a valid `URL` (bad base URL, path, or query).
    case invalidURL
    /// A transport-level failure occurred before a complete response was received (offline,
    /// timeout, connection lost, TLS failure). Carries the underlying `URLError`.
    case transport(URLError)
    /// The server responded with a non-2xx status code. Carries the `code` and any response
    /// `body` (often a JSON error payload you may want to decode for diagnostics).
    case unacceptableStatus(code: Int, body: Data?)
    /// The response body could not be decoded into the requested `Decodable` type. Carries a
    /// human-readable description of the underlying `DecodingError`.
    case decoding(message: String)
    /// A request body value could not be encoded. Carries a human-readable description.
    case encoding(message: String)
    /// A test/preview fixture resource could not be found in the given bundle. See ``Fixture``.
    case fixtureNotFound(name: String)
    /// An unexpected failure that does not fit the other cases. Carries a description.
    case unknown(message: String)

    /// The HTTP status code, when the error came from a server response.
    public var statusCode: Int? {
        if case let .unacceptableStatus(code, _) = self { return code }
        return nil
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL was invalid."
        case let .transport(error):
            return "Network transport failed: \(error.localizedDescription)"
        case let .unacceptableStatus(code, _):
            return "Server returned an unacceptable status code (\(code))."
        case let .decoding(message):
            return "Failed to decode the response: \(message)"
        case let .encoding(message):
            return "Failed to encode the request body: \(message)"
        case let .fixtureNotFound(name):
            return "Fixture '\(name)' was not found in the bundle."
        case let .unknown(message):
            return "An unexpected error occurred: \(message)"
        }
    }
}
