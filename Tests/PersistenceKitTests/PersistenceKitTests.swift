import XCTest
import SwiftData
@testable import PersistenceKit

@Model final class SampleItem { var name: String; init(name: String) { self.name = name } }

final class PersistenceKitTests: XCTestCase {
    func testInMemoryContainerBuilds() throws {
        let container = try PersistenceKit.container(for: [SampleItem.self], inMemory: true)
        XCTAssertNotNil(container)
    }
}
