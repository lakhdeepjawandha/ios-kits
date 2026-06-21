import SwiftData

/// Shared SwiftData stack helpers.
public enum PersistenceKit {
    /// Build a container for the given models. Use `inMemory: true` for tests/previews.
    public static func container(
        for types: [any PersistentModel.Type],
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(types)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// A minimal repository abstraction so view models don't touch SwiftData directly.
public protocol Repository {
    associatedtype Model: PersistentModel
    func all() throws -> [Model]
    func insert(_ model: Model) throws
    func delete(_ model: Model) throws
}
