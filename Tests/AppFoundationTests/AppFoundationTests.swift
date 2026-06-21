import XCTest
import Foundation
@testable import AppFoundation

final class FormatterTests: XCTestCase {
    func testAudFormatter() {
        XCTAssertEqual((12.5).audString, "$12.50")
        XCTAssertEqual((0.0).audString, "$0.00")
        XCTAssertEqual((1_234.56).audString, "$1,234.56")
    }

    func testPercentFormatter() {
        XCTAssertEqual((0.0).percentString, "0%")
        XCTAssertEqual((1.0).percentString, "100%")
        XCTAssertEqual((0.42).percentString, "42%")
    }

    func testRelativeDateFormatterNotEmpty() {
        let past = Date(timeIntervalSinceNow: -3600)
        XCTAssertFalse(past.relativeString.isEmpty)
    }
}

final class FeatureFlagTests: XCTestCase {
    private var store: FeatureFlags!
    private var defaults: UserDefaults!
    private static let suiteName = "com.test.AppFoundationTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)!
        // Clear previous test state
        defaults.removePersistentDomain(forName: Self.suiteName)
        store = FeatureFlags(defaults: defaults)
    }

    private static let boolFlag   = FeatureFlags.Flag<Bool>(key: "test.bool",   default: false)
    private static let intFlag    = FeatureFlags.Flag<Int>(key: "test.int",     default: 7)
    private static let stringFlag = FeatureFlags.Flag<String>(key: "test.str",  default: "hello")

    func testDefaultBool() {
        XCTAssertFalse(store[Self.boolFlag])
    }

    func testWriteReadBool() {
        store[Self.boolFlag] = true
        XCTAssertTrue(store[Self.boolFlag])
    }

    func testDefaultInt() {
        XCTAssertEqual(store[Self.intFlag], 7)
    }

    func testWriteReadInt() {
        store[Self.intFlag] = 42
        XCTAssertEqual(store[Self.intFlag], 42)
    }

    func testDefaultString() {
        XCTAssertEqual(store[Self.stringFlag], "hello")
    }

    func testWriteReadString() {
        store[Self.stringFlag] = "world"
        XCTAssertEqual(store[Self.stringFlag], "world")
    }

    func testReset() {
        store[Self.boolFlag] = true
        store.reset(Self.boolFlag)
        XCTAssertFalse(store[Self.boolFlag])
    }
}

final class DebouncerTests: XCTestCase {
    func testDebouncerFiresOnce() async throws {
        let debouncer = Debouncer(interval: 0.05)
        let counter = Counter()

        for _ in 0..<5 {
            await debouncer.call { await counter.increment() }
        }

        // Wait longer than the debounce interval
        try await Task.sleep(nanoseconds: 150_000_000)
        let count = await counter.value
        XCTAssertEqual(count, 1, "Debouncer should coalesce rapid calls into one")
    }

    func testDebouncerCancel() async throws {
        let debouncer = Debouncer(interval: 0.1)
        let counter = Counter()

        await debouncer.call { await counter.increment() }
        await debouncer.cancel()

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.value
        XCTAssertEqual(count, 0, "Cancelled debouncer should not fire")
    }
}

// Thread-safe counter helper
private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
