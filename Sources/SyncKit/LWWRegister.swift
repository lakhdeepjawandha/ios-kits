import Foundation

/// Last-write-wins register — the simplest CRDT building block, for a single value that should
/// reflect the most recent write across replicas.
///
/// Each write carries a `(timestamp, actor)` stamp. On merge, the value with the greater stamp wins.
/// The **actor** breaks ties when two replicas write at the exact same `timestamp`: without it,
/// `a.merged(with: b)` and `b.merged(with: a)` could disagree on equal timestamps and diverge. With
/// a per-replica actor id, the stamp ordering is total, so merges are commutative and convergent.
///
/// ```swift
/// var a = LWWRegister("draft", timestamp: t, actor: "A")
/// var b = LWWRegister("final", timestamp: t, actor: "B")
/// a.merge(b); b.merge(a)        // both converge to the same winner ("final" — actor "B" > "A")
/// // a == b
/// ```
public struct LWWRegister<Value: Equatable>: Equatable {
    /// The current value.
    public private(set) var value: Value
    /// The timestamp of the winning write.
    public private(set) var timestamp: Date
    /// The replica id of the winning write (tiebreaker for equal timestamps).
    public private(set) var actor: String

    /// Create a register.
    ///
    /// - Parameters:
    ///   - value: Initial value.
    ///   - timestamp: Write time. Default now.
    ///   - actor: Originating replica id (tiebreaker). Default `""`; pass a stable per-replica id
    ///     when multiple replicas may write concurrently.
    public init(_ value: Value, timestamp: Date = .now, actor: String = "") {
        self.value = value
        self.timestamp = timestamp
        self.actor = actor
    }

    /// Record a new write. Always advances this register to the new stamp.
    ///
    /// - Parameters:
    ///   - newValue: The new value.
    ///   - timestamp: Write time. Default now.
    ///   - actor: Originating replica id. Default keeps the existing actor.
    public mutating func setValue(_ newValue: Value, timestamp: Date = .now, actor: String? = nil) {
        self.value = newValue
        self.timestamp = timestamp
        if let actor { self.actor = actor }
    }

    /// Whether `other`'s stamp is strictly greater than this register's, under `(timestamp, actor)`
    /// lexicographic order.
    private func isOutranked(by other: LWWRegister) -> Bool {
        if other.timestamp != timestamp { return other.timestamp > timestamp }
        return other.actor > actor
    }
}

extension LWWRegister: Mergeable {
    public func merged(with other: LWWRegister) -> LWWRegister {
        isOutranked(by: other) ? other : self
    }
}

extension LWWRegister: Sendable where Value: Sendable {}
extension LWWRegister: Codable where Value: Codable {}
