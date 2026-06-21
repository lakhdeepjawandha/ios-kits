import Foundation

/// An example syncable entity that ties CRDT building blocks together: scalar fields as
/// ``LWWRegister``s and a collection as an ``ORSet``. Its ``merged(with:)`` merges each field
/// independently, so the whole document converges deterministically regardless of merge order.
///
/// Use it as a template for your own syncable models — pick `LWWRegister` for "latest value wins"
/// fields and `ORSet` for sets/tags/collections.
///
/// ```swift
/// var a = MergeableDocument(id: "note-1", title: "Draft", body: "", actor: "A")
/// var b = a
/// a.setTitle("Groceries", timestamp: t2, actor: "A")
/// b.addTag("urgent")
/// // converge in either order → identical result
/// let m1 = a.merged(with: b)
/// let m2 = b.merged(with: a)
/// // m1 == m2
/// ```
public struct MergeableDocument: Mergeable, Equatable, Sendable, Codable {
    /// Stable document identity (not merged — both replicas refer to the same document).
    public let id: String
    /// Title (latest write wins).
    public private(set) var title: LWWRegister<String>
    /// Body text (latest write wins).
    public private(set) var body: LWWRegister<String>
    /// Tags (observed-remove set; add-wins on conflict).
    public private(set) var tags: ORSet<String>

    /// Create a document.
    ///
    /// - Parameters:
    ///   - id: Stable identity shared across replicas.
    ///   - title: Initial title.
    ///   - body: Initial body.
    ///   - actor: This replica's id (used for LWW tiebreaks and OR-Set tags).
    ///   - timestamp: Initial write time. Default now.
    public init(id: String, title: String, body: String, actor: String, timestamp: Date = .now) {
        self.id = id
        self.title = LWWRegister(title, timestamp: timestamp, actor: actor)
        self.body = LWWRegister(body, timestamp: timestamp, actor: actor)
        self.tags = ORSet(actor: actor)
    }

    /// Update the title with a new write.
    public mutating func setTitle(_ value: String, timestamp: Date = .now, actor: String) {
        title.setValue(value, timestamp: timestamp, actor: actor)
    }

    /// Update the body with a new write.
    public mutating func setBody(_ value: String, timestamp: Date = .now, actor: String) {
        body.setValue(value, timestamp: timestamp, actor: actor)
    }

    /// Add a tag.
    public mutating func addTag(_ tag: String) { tags.add(tag) }

    /// Remove a tag.
    public mutating func removeTag(_ tag: String) { tags.remove(tag) }

    public func merged(with other: MergeableDocument) -> MergeableDocument {
        var result = self
        result.title = title.merged(with: other.title)
        result.body = body.merged(with: other.body)
        result.tags = tags.merged(with: other.tags)
        return result
    }
}
