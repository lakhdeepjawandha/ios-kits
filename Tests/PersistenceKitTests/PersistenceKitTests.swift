import XCTest
import SwiftData
@testable import PersistenceKit

// MARK: - Test model

@Model
final class TestItem {
    var name: String
    var score: Int

    init(name: String, score: Int = 0) {
        self.name = name
        self.score = score
    }
}

// MARK: - Container tests

final class ContainerTests: XCTestCase {

    func testContainerBuildsInMemory() throws {
        let c = try PersistenceKit.makeInMemoryContainer(for: [TestItem.self])
        XCTAssertNotNil(c)
    }

    func testContainerSignatureIsStable() throws {
        // Verifies the original public API hasn't changed.
        let c = try PersistenceKit.container(for: [TestItem.self], inMemory: true)
        XCTAssertNotNil(c)
    }

    func testMakeInMemoryContainerIsEquivalent() throws {
        let c1 = try PersistenceKit.container(for: [TestItem.self], inMemory: true)
        let c2 = try PersistenceKit.makeInMemoryContainer(for: [TestItem.self])
        XCTAssertNotNil(c1)
        XCTAssertNotNil(c2)
    }
}

// MARK: - SwiftDataRepository tests

@MainActor
final class SwiftDataRepositoryTests: XCTestCase {

    var container: ModelContainer!
    var repo: SwiftDataRepository<TestItem>!

    override func setUpWithError() throws {
        container = try PersistenceKit.makeInMemoryContainer(for: [TestItem.self])
        repo = SwiftDataRepository(context: container.mainContext)
    }

    // MARK: all()

    func testAllReturnsEmptyWhenNoData() throws {
        XCTAssertTrue(try repo.all().isEmpty)
    }

    // MARK: insert()

    func testInsertPersistsItem() throws {
        try repo.insert(TestItem(name: "Alpha"))
        let results = try repo.all()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Alpha")
    }

    func testInsertMultipleItems() throws {
        try repo.insert(TestItem(name: "A"))
        try repo.insert(TestItem(name: "B"))
        try repo.insert(TestItem(name: "C"))
        XCTAssertEqual(try repo.all().count, 3)
    }

    // MARK: delete()

    func testDeleteRemovesItem() throws {
        let item = TestItem(name: "ToDelete")
        try repo.insert(item)
        XCTAssertEqual(try repo.all().count, 1)

        try repo.delete(item)
        XCTAssertEqual(try repo.all().count, 0)
    }

    func testDeleteOnlyRemovesTargetItem() throws {
        let keep   = TestItem(name: "Keep")
        let remove = TestItem(name: "Remove")
        try repo.insert(keep)
        try repo.insert(remove)

        try repo.delete(remove)

        let remaining = try repo.all()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "Keep")
    }

    // MARK: fetch(_:) with predicate

    func testFetchWithPredicate() throws {
        try repo.insert(TestItem(name: "Match",   score: 10))
        try repo.insert(TestItem(name: "NoMatch", score: 5))

        let descriptor = FetchDescriptor<TestItem>(
            predicate: #Predicate { $0.score > 7 }
        )
        let results = try repo.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Match")
    }

    func testFetchWithSortDescriptor() throws {
        try repo.insert(TestItem(name: "B", score: 2))
        try repo.insert(TestItem(name: "A", score: 1))
        try repo.insert(TestItem(name: "C", score: 3))

        let descriptor = FetchDescriptor<TestItem>(
            sortBy: [SortDescriptor(\.score, order: .forward)]
        )
        let results = try repo.fetch(descriptor)
        XCTAssertEqual(results.map(\.name), ["A", "B", "C"])
    }

    func testFetchWithFetchLimit() throws {
        for i in 0..<5 {
            try repo.insert(TestItem(name: "Item\(i)"))
        }
        var descriptor = FetchDescriptor<TestItem>()
        descriptor.fetchLimit = 3
        XCTAssertEqual(try repo.fetch(descriptor).count, 3)
    }

    // MARK: Round-trip

    func testInsertFetchDeleteRoundTrip() throws {
        try repo.insert(TestItem(name: "RoundTrip", score: 99))

        let fetched = try repo.fetch(
            FetchDescriptor<TestItem>(predicate: #Predicate { $0.score == 99 })
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "RoundTrip")

        try repo.delete(fetched[0])
        XCTAssertTrue(try repo.all().isEmpty)
    }
}

// MARK: - KeyValueStore tests

final class KeyValueStoreTests: XCTestCase {

    var store: KeyValueStore!

    override func setUp() {
        store = KeyValueStore.ephemeral()
    }

    // MARK: Primitive Codable types

    func testSetAndGetString() throws {
        try store.set("hello", for: "key")
        let value: String? = store.get("key")
        XCTAssertEqual(value, "hello")
    }

    func testSetAndGetInt() throws {
        try store.set(42, for: "count")
        let value: Int? = store.get("count")
        XCTAssertEqual(value, 42)
    }

    func testSetAndGetBool() throws {
        try store.set(true, for: "flag")
        let value: Bool? = store.get("flag")
        XCTAssertEqual(value, true)
    }

    func testGetMissingKeyReturnsNil() {
        let value: String? = store.get("nonexistent")
        XCTAssertNil(value)
    }

    func testRemoveDeletesKey() throws {
        try store.set("will-be-gone", for: "temp")
        store.remove("temp")
        let value: String? = store.get("temp")
        XCTAssertNil(value)
    }

    func testRemoveAllWithPrefix() throws {
        try store.set("v1", for: "feature.enabled")
        try store.set("v2", for: "feature.count")
        try store.set("v3", for: "other.key")

        store.removeAll(withPrefix: "feature.")

        let e: String? = store.get("feature.enabled")
        let c: String? = store.get("feature.count")
        let o: String? = store.get("other.key")

        XCTAssertNil(e)
        XCTAssertNil(c)
        XCTAssertEqual(o, "v3")
    }

    // MARK: Codable struct types

    private struct Prefs: Codable, Equatable {
        var darkMode: Bool
        var fontSize: Double
    }

    func testCodableRoundTrip() throws {
        let prefs = Prefs(darkMode: true, fontSize: 16.0)
        try store.set(prefs, for: "prefs")
        let loaded: Prefs? = store.get("prefs")
        XCTAssertEqual(loaded, prefs)
    }

    func testCodableArrayRoundTrip() throws {
        let tags = ["swift", "ios", "swiftdata"]
        try store.set(tags, for: "tags")
        let loaded: [String]? = store.get("tags")
        XCTAssertEqual(loaded, tags)
    }

    func testCodableMissingKeyReturnsNil() {
        let value: Prefs? = store.get("noPrefs")
        XCTAssertNil(value)
    }

    func testEphemeralStoreIsIsolated() throws {
        let store1 = KeyValueStore.ephemeral()
        let store2 = KeyValueStore.ephemeral()

        try store1.set("exclusive", for: "shared_key")

        let fromStore2: String? = store2.get("shared_key")
        XCTAssertNil(fromStore2, "Ephemeral stores must not share state")
    }
}

// MARK: - Preview / seeder helpers tests

@MainActor
final class PreviewHelpersTests: XCTestCase {

    func testSeedSampleData() throws {
        let container = try PersistenceKit.makeInMemoryContainer(for: [TestItem.self])

        let seeder: SampleDataSeeder = { ctx in
            ctx.insert(TestItem(name: "Seed1"))
            ctx.insert(TestItem(name: "Seed2"))
            try ctx.save()
        }

        try PersistenceKit.seedSampleData(into: container, seeders: [seeder])

        let repo = SwiftDataRepository<TestItem>(context: container.mainContext)
        let all = try repo.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.map(\.name).contains("Seed1"))
        XCTAssertTrue(all.map(\.name).contains("Seed2"))
    }

    func testMultipleSeedersRunInOrder() throws {
        let container = try PersistenceKit.makeInMemoryContainer(for: [TestItem.self])

        var order: [String] = []
        let s1: SampleDataSeeder = { ctx in order.append("first");  try ctx.save() }
        let s2: SampleDataSeeder = { ctx in order.append("second"); try ctx.save() }

        try PersistenceKit.seedSampleData(into: container, seeders: [s1, s2])
        XCTAssertEqual(order, ["first", "second"])
    }
}
