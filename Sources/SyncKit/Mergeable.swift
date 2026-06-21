import Foundation

/// A state-based CRDT value that converges when merged.
///
/// A correct conformer's ``merged(with:)`` must be:
/// - **commutative**: `a.merged(with: b) == b.merged(with: a)`
/// - **associative**: `a.merged(with: b).merged(with: c) == a.merged(with: b.merged(with: c))`
/// - **idempotent**: `a.merged(with: a) == a`
///
/// These three laws guarantee that replicas converge to the same state regardless of the order or
/// number of times changes are exchanged — the foundation of offline-first sync.
public protocol Mergeable {
    /// Merge another value of the same type, returning the converged result.
    func merged(with other: Self) -> Self
}

public extension Mergeable {
    /// In-place convenience for ``merged(with:)``.
    mutating func merge(_ other: Self) {
        self = merged(with: other)
    }
}
