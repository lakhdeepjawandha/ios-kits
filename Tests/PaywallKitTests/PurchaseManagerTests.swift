import XCTest
import StoreKit
@testable import PaywallKit

// MARK: - Entitlement mapping (pure logic)

final class ProductKindTests: XCTestCase {

    func testBridgesFromStoreKitProductType() {
        XCTAssertEqual(ProductKind(.consumable), .consumable)
        XCTAssertEqual(ProductKind(.nonConsumable), .nonConsumable)
        XCTAssertEqual(ProductKind(.autoRenewable), .autoRenewable)
        XCTAssertEqual(ProductKind(.nonRenewable), .nonRenewable)
    }

    func testRestorableEntitlementClassification() {
        XCTAssertTrue(ProductKind.nonConsumable.grantsRestorableEntitlement)
        XCTAssertTrue(ProductKind.autoRenewable.grantsRestorableEntitlement)
        XCTAssertTrue(ProductKind.nonRenewable.grantsRestorableEntitlement)
        XCTAssertFalse(ProductKind.consumable.grantsRestorableEntitlement)
    }

    func testConsumableEffectGrantsMappedCredits() {
        let effect = ProductKind.consumable.effect(productID: "credits.10",
                                                   creditValues: ["credits.10": 10])
        XCTAssertEqual(effect, .credits(productID: "credits.10", amount: 10))
    }

    func testConsumableEffectGrantsZeroWhenUnmapped() {
        let effect = ProductKind.consumable.effect(productID: "credits.unknown", creditValues: [:])
        XCTAssertEqual(effect, .credits(productID: "credits.unknown", amount: 0))
    }

    func testDurablePurchasesMapToEntitlement() {
        XCTAssertEqual(ProductKind.nonConsumable.effect(productID: "pro.lifetime", creditValues: [:]),
                       .entitlement(productID: "pro.lifetime"))
        XCTAssertEqual(ProductKind.autoRenewable.effect(productID: "pro.yearly", creditValues: [:]),
                       .entitlement(productID: "pro.yearly"))
        XCTAssertEqual(ProductKind.nonRenewable.effect(productID: "pass.season", creditValues: [:]),
                       .entitlement(productID: "pass.season"))
    }

    func testEntitlementIgnoresCreditValues() {
        // A non-consumable that happens to share an id with a credit map entry is still an entitlement.
        let effect = ProductKind.nonConsumable.effect(productID: "pro.lifetime",
                                                     creditValues: ["pro.lifetime": 999])
        XCTAssertEqual(effect, .entitlement(productID: "pro.lifetime"))
    }
}

// MARK: - Credits ledger

final class CreditsLedgerTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString) ?? .standard
    }

    func testStartsAtZero() {
        XCTAssertEqual(CreditsLedger(defaults: makeDefaults()).balance, 0)
    }

    func testGrantAddsToBalance() {
        let ledger = CreditsLedger(defaults: makeDefaults())
        ledger.grant(10)
        ledger.grant(5)
        XCTAssertEqual(ledger.balance, 15)
    }

    func testSpendDeductsWhenSufficient() {
        let ledger = CreditsLedger(defaults: makeDefaults())
        ledger.grant(10)
        XCTAssertTrue(ledger.spend(3))
        XCTAssertEqual(ledger.balance, 7)
    }

    func testSpendFailsWhenInsufficient() {
        let ledger = CreditsLedger(defaults: makeDefaults())
        ledger.grant(2)
        XCTAssertFalse(ledger.spend(5))
        XCTAssertEqual(ledger.balance, 2, "Balance must be unchanged on a failed spend")
    }

    func testNonPositiveAmountsAreIgnored() {
        let ledger = CreditsLedger(defaults: makeDefaults())
        ledger.grant(10)
        ledger.grant(0)
        ledger.grant(-5)
        XCTAssertEqual(ledger.balance, 10)
        XCTAssertFalse(ledger.spend(0))
        XCTAssertFalse(ledger.spend(-3))
        XCTAssertEqual(ledger.balance, 10)
    }

    func testPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let key = "test.credits"
        CreditsLedger(defaults: defaults, key: key).grant(7)
        XCTAssertEqual(CreditsLedger(defaults: defaults, key: key).balance, 7)
    }

    func testResetClearsBalance() {
        let ledger = CreditsLedger(defaults: makeDefaults())
        ledger.grant(9)
        ledger.reset()
        XCTAssertEqual(ledger.balance, 0)
    }
}

// MARK: - PurchaseManager defaults & credit plumbing

final class PurchaseManagerTests: XCTestCase {

    private func makeLedger() -> CreditsLedger {
        CreditsLedger(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
    }

    @MainActor func testStartsWithoutEntitlements() {
        let manager = PurchaseManager(
            productIDs: ["pro.yearly", "pro.lifetime", "credits.10"],
            creditValues: ["credits.10": 10],
            ledger: makeLedger()
        )
        XCTAssertFalse(manager.hasEntitlement)
        XCTAssertTrue(manager.entitledProductIDs.isEmpty)
        XCTAssertEqual(manager.subscriptionState, .notSubscribed)
        XCTAssertEqual(manager.creditBalance, 0)
        XCTAssertFalse(manager.isEntitled(to: "pro.lifetime"))
    }

    @MainActor func testCreditConvenienceMethodsTrackLedger() {
        let manager = PurchaseManager(productIDs: ["credits.10"], ledger: makeLedger())
        manager.grantCredits(10)
        XCTAssertEqual(manager.creditBalance, 10)
        XCTAssertTrue(manager.spendCredits(4))
        XCTAssertEqual(manager.creditBalance, 6)
        XCTAssertFalse(manager.spendCredits(100))
        XCTAssertEqual(manager.creditBalance, 6)
    }
}

// MARK: - Bundled config covers all product types

final class StoreKitConfigurationProductTypeTests: XCTestCase {

    func testBundledConfigIncludesNonConsumableAndConsumable() throws {
        let url = try XCTUnwrap(StoreKitConfiguration.sampleURL)
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])

        let byID = Dictionary(uniqueKeysWithValues: products.compactMap { product -> (String, String)? in
            guard let id = product["productID"] as? String, let type = product["type"] as? String else { return nil }
            return (id, type)
        })

        XCTAssertEqual(byID["pro.lifetime"], "NonConsumable")
        XCTAssertEqual(byID["credits.10"], "Consumable")
    }

    func testBundledConfigStillDefinesSubscriptions() throws {
        let url = try XCTUnwrap(StoreKitConfiguration.sampleURL)
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(json["subscriptionGroups"] as? [[String: Any]])
        let subs = groups.flatMap { ($0["subscriptions"] as? [[String: Any]]) ?? [] }
        let ids = subs.compactMap { $0["productID"] as? String }
        XCTAssertTrue(ids.contains("pro.weekly"))
        XCTAssertTrue(ids.contains("pro.yearly"))
    }
}
