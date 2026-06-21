import SwiftData

// MARK: - Preview / test container helpers

public extension PersistenceKit {

    /// Create a fully isolated, in-memory ``ModelContainer`` for use in Xcode previews
    /// and unit tests.
    ///
    /// This is a convenience alias for ``container(for:inMemory:)`` with `inMemory: true`,
    /// provided under a descriptive name so call-sites are self-documenting:
    ///
    /// ```swift
    /// // In a SwiftUI preview:
    /// #Preview {
    ///     let c = try! PersistenceKit.makeInMemoryContainer(for: [Item.self])
    ///     return ContentView()
    ///         .modelContainer(c)
    /// }
    ///
    /// // In a unit test:
    /// let container = try PersistenceKit.makeInMemoryContainer(for: [Item.self])
    /// let repo = SwiftDataRepository<Item>(context: container.mainContext)
    /// ```
    ///
    /// - Parameter types: The model types whose schema the container should manage.
    /// - Returns: An in-memory ``ModelContainer``.
    static func makeInMemoryContainer(for types: [any PersistentModel.Type]) throws -> ModelContainer {
        try container(for: types, inMemory: true)
    }
}

// MARK: - Sample-data seeding

/// A closure that inserts sample instances into a context and saves.
///
/// Implement one per model type and pass it to ``seedSampleData(into:seeders:)``:
///
/// ```swift
/// let itemSeeder: SampleDataSeeder = { ctx in
///     ctx.insert(Item(name: "Preview Item 1"))
///     ctx.insert(Item(name: "Preview Item 2"))
///     try ctx.save()
/// }
/// try PersistenceKit.seedSampleData(into: container, seeders: [itemSeeder])
/// ```
public typealias SampleDataSeeder = (ModelContext) throws -> Void

public extension PersistenceKit {

    /// Run every seeder against the container's `mainContext`.
    ///
    /// Call this once after ``makeInMemoryContainer(for:)`` to populate previews or
    /// test fixtures with realistic data:
    ///
    /// ```swift
    /// let container = try PersistenceKit.makeInMemoryContainer(for: [Item.self])
    /// try PersistenceKit.seedSampleData(into: container, seeders: [itemSeeder])
    /// ```
    ///
    /// - Parameters:
    ///   - container: The target container.
    ///   - seeders: An ordered array of ``SampleDataSeeder`` closures to run.
    @MainActor
    static func seedSampleData(
        into container: ModelContainer,
        seeders: [SampleDataSeeder]
    ) throws {
        let context = container.mainContext
        for seeder in seeders {
            try seeder(context)
        }
    }
}
