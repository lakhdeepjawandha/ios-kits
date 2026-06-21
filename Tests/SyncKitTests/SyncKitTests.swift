import XCTest
@testable import SyncKit

private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

// MARK: - LWWRegister

final class LWWRegisterTests: XCTestCase {

    func testLaterTimestampWins() {
        let a = LWWRegister("old", timestamp: date(1), actor: "A")
        let b = LWWRegister("new", timestamp: date(2), actor: "B")
        XCTAssertEqual(a.merged(with: b).value, "new")
        XCTAssertEqual(b.merged(with: a).value, "new")
    }

    func testEqualTimestampBrokenByActorDeterministically() {
        let a = LWWRegister("from-A", timestamp: date(5), actor: "A")
        let b = LWWRegister("from-B", timestamp: date(5), actor: "B")
        // Commutative even on a timestamp tie.
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
        XCTAssertEqual(a.merged(with: b).value, "from-B") // "B" > "A"
    }

    func testIdempotent() {
        let a = LWWRegister("x", timestamp: date(1), actor: "A")
        XCTAssertEqual(a.merged(with: a), a)
    }

    func testCommutativeAndAssociative() {
        let a = LWWRegister("a", timestamp: date(1), actor: "A")
        let b = LWWRegister("b", timestamp: date(2), actor: "B")
        let c = LWWRegister("c", timestamp: date(3), actor: "C")
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
        XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
    }

    func testSetValueAdvancesStamp() {
        var r = LWWRegister("x", timestamp: date(1), actor: "A")
        r.setValue("y", timestamp: date(2), actor: "A")
        XCTAssertEqual(r.value, "y")
        XCTAssertEqual(r.timestamp, date(2))
    }
}

// MARK: - ORSet

final class ORSetTests: XCTestCase {

    func testAddContainsRemove() {
        var set = ORSet<String>(actor: "A")
        XCTAssertFalse(set.contains("x"))
        set.add("x")
        XCTAssertTrue(set.contains("x"))
        XCTAssertEqual(set.elements, ["x"])
        set.remove("x")
        XCTAssertFalse(set.contains("x"))
        XCTAssertTrue(set.elements.isEmpty)
    }

    func testReAddAfterRemove() {
        var set = ORSet<String>(actor: "A")
        set.add("x"); set.remove("x")
        set.add("x") // a new, un-tombstoned tag
        XCTAssertTrue(set.contains("x"))
    }

    func testMergeIsCommutativeAndIdempotent() {
        var a = ORSet<Int>(actor: "A"); a.add(1); a.add(2)
        var b = ORSet<Int>(actor: "B"); b.add(2); b.add(3)
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
        XCTAssertEqual(a.merged(with: a), a)
        XCTAssertEqual(a.merged(with: b).elements, [1, 2, 3])
    }

    func testAddWinsOverConcurrentRemoveNoDataLoss() {
        // Both replicas observe "x".
        var a = ORSet<String>(actor: "A"); a.add("x")
        var b = a.merged(with: ORSet<String>(actor: "B")) // b sees a's "x"
        // A removes the "x" it saw; B concurrently re-adds "x" with a fresh tag.
        a.remove("x")
        b.add("x")
        // Converge in both orders — the concurrent add survives.
        let m1 = a.merged(with: b)
        let m2 = b.merged(with: a)
        XCTAssertEqual(m1, m2)
        XCTAssertTrue(m1.contains("x"), "concurrent add must win (no data loss)")
    }

    func testConcurrentRemoveOfSameObservedTagsRemoves() {
        // When both replicas remove the same observed adds (no concurrent re-add), it's gone.
        var a = ORSet<String>(actor: "A"); a.add("x")
        var b = a.merged(with: ORSet<String>(actor: "B"))
        a.remove("x")
        b.remove("x")
        XCTAssertFalse(a.merged(with: b).contains("x"))
    }
}

// MARK: - MergeableDocument convergence

final class MergeableDocumentTests: XCTestCase {

    func testConcurrentEditsConvergeRegardlessOfOrder() {
        let base = MergeableDocument(id: "doc", title: "Untitled", body: "", actor: "seed", timestamp: date(0))
        var a = base
        var b = base

        // Replica A: rename + add a tag.
        a.setTitle("Groceries", timestamp: date(10), actor: "A")
        a.addTag("shopping")
        a.addTag("urgent")

        // Replica B: edit body + add a tag + remove one A added? (B hasn't seen A's tags)
        b.setBody("milk, eggs", timestamp: date(11), actor: "B")
        b.addTag("home")

        // Merge in both orders.
        let ab = a.merged(with: b)
        let ba = b.merged(with: a)
        XCTAssertEqual(ab, ba, "document must converge regardless of merge order")

        // Field-level expectations.
        XCTAssertEqual(ab.title.value, "Groceries")          // only A wrote the title
        XCTAssertEqual(ab.body.value, "milk, eggs")          // only B wrote the body
        XCTAssertEqual(ab.tags.elements, ["shopping", "urgent", "home"])
    }

    func testThreeReplicaConvergenceAnyOrder() {
        let base = MergeableDocument(id: "doc", title: "t", body: "b", actor: "seed", timestamp: date(0))
        var a = base, b = base, c = base
        a.setTitle("A-title", timestamp: date(3), actor: "A"); a.addTag("a")
        b.setTitle("B-title", timestamp: date(2), actor: "B"); b.addTag("b")
        c.setBody("C-body", timestamp: date(5), actor: "C"); c.addTag("c")

        let order1 = a.merged(with: b).merged(with: c)
        let order2 = c.merged(with: a).merged(with: b)
        let order3 = b.merged(with: c).merged(with: a)
        XCTAssertEqual(order1, order2)
        XCTAssertEqual(order2, order3)
        XCTAssertEqual(order1.title.value, "A-title")        // latest title timestamp (3 > 2)
        XCTAssertEqual(order1.body.value, "C-body")
        XCTAssertEqual(order1.tags.elements, ["a", "b", "c"])
    }

    func testTitleTieBrokenByActor() {
        let base = MergeableDocument(id: "doc", title: "x", body: "", actor: "seed", timestamp: date(0))
        var a = base, b = base
        a.setTitle("A", timestamp: date(9), actor: "A")
        b.setTitle("B", timestamp: date(9), actor: "B") // same timestamp
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
        XCTAssertEqual(a.merged(with: b).title.value, "B")
    }

    func testCodableRoundTrip() throws {
        var doc = MergeableDocument(id: "doc", title: "T", body: "B", actor: "A", timestamp: date(1))
        doc.addTag("x"); doc.addTag("y")
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(MergeableDocument.self, from: data)
        XCTAssertEqual(decoded, doc)
    }
}

// MARK: - Transport & engine

final class TransportTests: XCTestCase {

    func testMockTransportPushPull() async throws {
        let transport = MockTransport<MergeableDocument>()
        let doc = MergeableDocument(id: "d", title: "T", body: "", actor: "A", timestamp: date(1))
        try await transport.push(doc, for: "d")
        let pulled = try await transport.pull("d")
        XCTAssertEqual(pulled, doc)
        let missing = try await transport.pull("missing")
        XCTAssertNil(missing)
    }

    func testPushMergesServerSide() async throws {
        let transport = MockTransport<MergeableDocument>()
        let base = MergeableDocument(id: "d", title: "x", body: "", actor: "seed", timestamp: date(0))
        var a = base, b = base
        a.setTitle("A", timestamp: date(10), actor: "A")
        b.addTag("tag")

        try await transport.push(a, for: "d")
        try await transport.push(b, for: "d") // merges with A's pushed state
        let merged = try await transport.pull("d")
        XCTAssertEqual(merged?.title.value, "A")
        XCTAssertEqual(merged?.tags.elements, ["tag"])
    }

    func testSyncEngineConvergesTwoReplicas() async throws {
        let transport = MockTransport<MergeableDocument>()
        let engine = SyncEngine(transport: transport)
        let base = MergeableDocument(id: "d", title: "x", body: "", actor: "seed", timestamp: date(0))

        var a = base, b = base
        a.setTitle("Groceries", timestamp: date(10), actor: "A"); a.addTag("shopping")
        b.setBody("milk", timestamp: date(11), actor: "B"); b.addTag("home")

        // Offline-first: each replica syncs (pull-merge-push) over the shared transport.
        a = try await engine.sync(a, id: "d")
        b = try await engine.sync(b, id: "d")
        a = try await engine.sync(a, id: "d") // A pulls B's changes

        XCTAssertEqual(a.title.value, "Groceries")
        XCTAssertEqual(a.body.value, "milk")
        XCTAssertEqual(a.tags.elements, ["shopping", "home"])

        // Both replicas, and the server, agree.
        let server = try await transport.pull("d")
        XCTAssertEqual(a, server)
        b = try await engine.sync(b, id: "d")
        XCTAssertEqual(a, b)
    }
}
