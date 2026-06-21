import SwiftData

/// A generic ``Repository`` backed by a SwiftData ``ModelContext``.
///
/// Inject this type into view-models via the ``Repository`` protocol so the
/// concrete SwiftData dependency stays out of business logic:
///
/// ```swift
/// let repo = SwiftDataRepository<Item>(context: container.mainContext)
/// let all  = try repo.all()
/// ```
public struct SwiftDataRepository<Model: PersistentModel>: Repository {

    private let context: ModelContext

    /// Create a repository that operates on the supplied context.
    ///
    /// - Parameter context: The ``ModelContext`` to read from and write to.
    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Repository

    /// Return every stored instance of `Model`, unordered.
    public func all() throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }

    /// Insert `model` into the context and save.
    public func insert(_ model: Model) throws {
        context.insert(model)
        try context.save()
    }

    /// Delete `model` from the context and save.
    public func delete(_ model: Model) throws {
        context.delete(model)
        try context.save()
    }

    // MARK: Extended API

    /// Execute an arbitrary fetch using the supplied descriptor.
    ///
    /// Use this for filtered or sorted queries:
    ///
    /// ```swift
    /// var desc = FetchDescriptor<Item>(
    ///     predicate: #Predicate { $0.isArchived == false },
    ///     sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    /// )
    /// desc.fetchLimit = 20
    /// let recent = try repo.fetch(desc)
    /// ```
    ///
    /// - Parameter descriptor: A ``FetchDescriptor`` with optional predicate, sort, and limit.
    /// - Returns: The matched model instances.
    public func fetch(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        try context.fetch(descriptor)
    }
}
