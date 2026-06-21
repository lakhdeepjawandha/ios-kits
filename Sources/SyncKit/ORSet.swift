import Foundation

/// An **observed-remove set** (OR-Set) CRDT: a set that converges under concurrent add/remove.
///
/// The classic problem with naive replicated sets is the add/remove conflict: if one replica adds an
/// element while another removes it, what's the result? An OR-Set resolves this with **unique tags**:
/// every `add` mints a fresh tag for the element, and `remove` tombstones only the tags it has
/// *observed*. An element is present while it has at least one un-tombstoned tag. The practical
/// consequence is **add-wins**: a concurrent add (whose new tag the remover never saw) survives, so
/// there's no accidental data loss.
///
/// Merging is the union of all add-tags and all tombstones — commutative, associative, and
/// idempotent — so replicas converge regardless of order.
///
/// ```swift
/// var a = ORSet<String>(actor: "A"); a.add("x")
/// var b = a; b = b.merged(with: a)      // both see "x"
/// a.remove("x")                          // A tombstones the tag it saw
/// b.add("x")                             // B concurrently re-adds with a new tag
/// // after merge, "x" is present (add wins) — no data loss
/// ```
public struct ORSet<Element: Hashable> {

    /// A globally-unique add identity: the originating replica plus a monotonic counter.
    public struct Tag: Hashable, Codable, Sendable {
        public let actor: String
        public let counter: UInt64
    }

    /// This replica's id, used to mint unique tags.
    public let actor: String
    private var counter: UInt64 = 0
    /// Per-element set of add-tags ever applied.
    private var adds: [Element: Set<Tag>] = [:]
    /// Tags that have been observed-removed.
    private var tombstones: Set<Tag> = []

    /// Create an empty OR-Set for a replica.
    ///
    /// - Parameter actor: A stable id unique to this replica (used for tag uniqueness).
    public init(actor: String) {
        self.actor = actor
    }

    /// Add an element (mints a new unique tag).
    public mutating func add(_ element: Element) {
        counter += 1
        adds[element, default: []].insert(Tag(actor: actor, counter: counter))
    }

    /// Remove an element by tombstoning every tag this replica has currently observed for it.
    /// Concurrent adds elsewhere (with tags not yet seen here) are unaffected.
    public mutating func remove(_ element: Element) {
        guard let tags = adds[element] else { return }
        tombstones.formUnion(tags)
    }

    /// Whether the element is currently present (has an un-tombstoned add-tag).
    public func contains(_ element: Element) -> Bool {
        guard let tags = adds[element] else { return false }
        return !tags.isSubset(of: tombstones)
    }

    /// The set of currently-present elements.
    public var elements: Set<Element> {
        Set(adds.keys.filter { contains($0) })
    }

    /// The number of currently-present elements.
    public var count: Int { elements.count }
}

extension ORSet: Mergeable {
    public func merged(with other: ORSet) -> ORSet {
        var result = self                          // keeps this replica's actor/counter for future adds
        for (element, tags) in other.adds {
            result.adds[element, default: []].formUnion(tags)
        }
        result.tombstones.formUnion(other.tombstones)
        return result
    }
}

extension ORSet: Equatable {
    /// Two OR-Sets are equal when their CRDT state (adds + tombstones) matches. The per-replica
    /// `actor`/`counter` minting state is intentionally excluded, so two replicas that have
    /// converged compare equal even though they mint future tags differently.
    public static func == (lhs: ORSet, rhs: ORSet) -> Bool {
        lhs.adds == rhs.adds && lhs.tombstones == rhs.tombstones
    }
}

extension ORSet: Sendable where Element: Sendable {}
extension ORSet: Codable where Element: Codable {}
