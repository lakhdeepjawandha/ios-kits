import XCTest
@testable import PaywallKit

final class PaywallKitTests: XCTestCase {
    @MainActor func testStartsWithoutPro() {
        let manager = SubscriptionManager(productIDs: ["pro.weekly", "pro.yearly"])
        XCTAssertFalse(manager.hasPro)
        XCTAssertTrue(manager.purchasedProductIDs.isEmpty)
    }
}
