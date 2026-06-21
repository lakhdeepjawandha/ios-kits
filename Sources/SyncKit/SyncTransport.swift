import Foundation

/// Errors thrown by sync transports.
public enum SyncError: Error, Equatable {
    /// The transport needs configuration the current build can't provide (e.g. a paid account /
    /// iCloud container). Carries a message.
    case notConfigured(String)
    /// An operation isn't supported by this transport.
    case unsupported(String)
}

/// A backend that exchanges ``Mergeable`` documents between replicas.
///
/// The merge logic is local and account-free; the *transport* is where data crosses the network.
/// Keeping it behind this protocol lets apps sync against an in-memory ``MockTransport`` (tests,
/// previews, sandbox) and swap in ``CloudKitTransport`` once a paid account and iCloud container
/// exist — with no change to call sites or merge code.
///
/// Implementations should merge on `push` (so a replica never clobbers newer remote state) — see
/// ``MockTransport``.
public protocol SyncTransport: Sendable {
    /// The document type exchanged. Must be ``Mergeable`` so the transport can converge state.
    associatedtype Document: Mergeable

    /// Push a document for an id, merging with any existing remote state.
    func push(_ document: Document, for id: String) async throws

    /// Pull the current document for an id, or `nil` if none exists remotely.
    func pull(_ id: String) async throws -> Document?

    /// Pull all documents the transport holds, keyed by id.
    func pullAll() async throws -> [String: Document]
}

/// An in-memory ``SyncTransport`` for tests, previews, and offline/sandbox builds. Thread-safe via
/// actor isolation; `push` merges with existing state so concurrent pushes converge just like a real
/// CRDT backend.
public actor MockTransport<Document: Mergeable & Sendable>: SyncTransport {
    private var store: [String: Document] = [:]

    /// Create an empty transport, optionally seeded with documents.
    public init(seed: [String: Document] = [:]) {
        self.store = seed
    }

    public func push(_ document: Document, for id: String) async throws {
        store[id] = store[id]?.merged(with: document) ?? document
    }

    public func pull(_ id: String) async throws -> Document? {
        store[id]
    }

    public func pullAll() async throws -> [String: Document] {
        store
    }
}

/// A small offline-first helper: pull remote state, merge it into the local document, push the
/// merged result back, and return it. Running it on each replica drives convergence.
///
/// ```swift
/// let engine = SyncEngine(transport: transport)
/// localDoc = try await engine.sync(localDoc, id: localDoc.id)
/// ```
public struct SyncEngine<Transport: SyncTransport>: Sendable {
    /// The backing transport.
    public let transport: Transport

    /// Create an engine over a transport.
    public init(transport: Transport) {
        self.transport = transport
    }

    /// Pull, merge into `local`, push, and return the merged document.
    ///
    /// - Parameters:
    ///   - local: The local document state.
    ///   - id: The document id.
    /// - Returns: The merged document (local ⊕ remote).
    @discardableResult
    public func sync(_ local: Transport.Document, id: String) async throws -> Transport.Document {
        let remote = try await transport.pull(id)
        let merged = remote.map { local.merged(with: $0) } ?? local
        try await transport.push(merged, for: id)
        return merged
    }
}
