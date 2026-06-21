import Foundation

/// Async REST client. Swap `URLProtocol` mocks in for tests.
public protocol APIClient: Sendable {
    func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T
}

public struct LiveAPIClient: APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(T.self, from: data)
    }
}
