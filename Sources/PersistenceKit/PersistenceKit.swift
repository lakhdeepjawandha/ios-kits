import SwiftData

// MARK: - Container

/// Shared SwiftData stack helpers.
public enum PersistenceKit {

    /// Build a ``ModelContainer`` for the given models.
    ///
    /// - Parameters:
    ///   - types: The persistent model types to include in the schema.
    ///   - inMemory: Pass `true` for tests and SwiftUI previews so no data is written to disk.
    /// - Returns: A configured ``ModelContainer``.
    /// - Throws: Any error thrown by ``ModelContainer``'s initialiser.
    public static func container(
        for types: [any PersistentModel.Type],
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(types)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

// MARK: - Repository protocol

/// A minimal persistence abstraction that keeps view-models free of SwiftData imports.
///
/// Concrete conformances typically wrap a ``ModelContext`` and can be swapped with
/// in-memory fakes during testing.
public protocol Repository<Model> {
    associatedtype Model: PersistentModel

    /// Return every stored instance.
    func all() throws -> [Model]

    /// Persist a new instance.
    func insert(_ model: Model) throws

    /// Remove an existing instance.
    func delete(_ model: Model) throws
}

// MARK: - Schema migration pattern
//
// When a @Model type evolves, adopt SchemaMigrationPlan:
//
//   enum AppMigrationPlan: SchemaMigrationPlan {
//       static var schemas: [VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
//
//       static var stages: [MigrationStage] {
//           [MigrationStage.lightweight(fromVersion: SchemaV1.self,
//                                       toVersion:   SchemaV2.self)]
//       }
//   }
//
//   enum SchemaV1: VersionedSchema {
//       static var versionIdentifier = Schema.Version(1, 0, 0)
//       static var models: [any PersistentModel.Type] { [Item.self] }
//       // V1 shape lives here (kept for migration reference).
//   }
//
//   enum SchemaV2: VersionedSchema {
//       static var versionIdentifier = Schema.Version(2, 0, 0)
//       static var models: [any PersistentModel.Type] { [Item.self] }
//   }
//
// Then pass the plan to ModelContainer:
//
//   ModelContainer(
//       for: Schema(SchemaV2.models),
//       migrationPlan: AppMigrationPlan.self,
//       configurations: [config]
//   )
//
// Use `.custom` stages instead of `.lightweight` when you need a closure to
// transform rows (e.g., splitting a `fullName` column into `firstName`/`lastName`).
