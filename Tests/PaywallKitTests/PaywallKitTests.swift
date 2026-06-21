import XCTest
import StoreKit
@testable import PaywallKit

// MARK: - Manager defaults

final class PaywallKitTests: XCTestCase {
    @MainActor func testStartsWithoutPro() {
        let manager = SubscriptionManager(productIDs: ["pro.weekly", "pro.yearly"])
        XCTAssertFalse(manager.hasPro)
        XCTAssertTrue(manager.purchasedProductIDs.isEmpty)
        XCTAssertEqual(manager.subscriptionState, .notSubscribed)
        XCTAssertTrue(manager.introEligibleProductIDs.isEmpty)
    }
}

// MARK: - Status mapping (pure logic)

final class SubscriptionStateTests: XCTestCase {

    func testSubscribedWithoutTrialIsActive() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .subscribed, isInTrial: false), .active)
    }

    func testSubscribedWithTrialIsTrial() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .subscribed, isInTrial: true), .trial)
    }

    func testGracePeriodMapsThrough() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .inGracePeriod, isInTrial: false), .inGracePeriod)
    }

    func testBillingRetryMapsThrough() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .inBillingRetryPeriod, isInTrial: false), .inBillingRetry)
    }

    func testExpiredMapsThrough() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .expired, isInTrial: false), .expired)
    }

    func testRevokedMapsThrough() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .revoked, isInTrial: false), .revoked)
    }

    func testUnknownIsNotSubscribed() {
        XCTAssertEqual(SubscriptionState.resolve(renewal: .unknown, isInTrial: false), .notSubscribed)
    }

    func testTrialFlagIgnoredOutsideSubscribed() {
        // A trial flag only matters while subscribed; it must not flip an expired state to trial.
        XCTAssertEqual(SubscriptionState.resolve(renewal: .expired, isInTrial: true), .expired)
    }

    func testEntitlementByState() {
        XCTAssertTrue(SubscriptionState.trial.isEntitled)
        XCTAssertTrue(SubscriptionState.active.isEntitled)
        XCTAssertTrue(SubscriptionState.inGracePeriod.isEntitled)
        XCTAssertFalse(SubscriptionState.inBillingRetry.isEntitled)
        XCTAssertFalse(SubscriptionState.expired.isEntitled)
        XCTAssertFalse(SubscriptionState.revoked.isEntitled)
        XCTAssertFalse(SubscriptionState.notSubscribed.isEntitled)
    }
}

// MARK: - Intro-offer text formatting (pure logic)

final class IntroOfferTextTests: XCTestCase {

    func testFreeTrialWeekly() {
        let text = IntroOffer.describe(paymentMode: .freeTrial,
                                       periodUnit: .week,
                                       periodValue: 1,
                                       offerDisplayPrice: "$0.00",
                                       standardDisplayPrice: "$1.99",
                                       standardPeriodUnit: .week)
        XCTAssertEqual(text, "1-week free trial, then $1.99/week")
    }

    func testFreeTrialMultiDayUsesSingularAdjective() {
        let text = IntroOffer.describe(paymentMode: .freeTrial,
                                       periodUnit: .day,
                                       periodValue: 3,
                                       offerDisplayPrice: "$0.00",
                                       standardDisplayPrice: "$59.99",
                                       standardPeriodUnit: .year)
        XCTAssertEqual(text, "3-day free trial, then $59.99/year")
    }

    func testPayUpFront() {
        let text = IntroOffer.describe(paymentMode: .payUpFront,
                                       periodUnit: .month,
                                       periodValue: 3,
                                       offerDisplayPrice: "$4.99",
                                       standardDisplayPrice: "$1.99",
                                       standardPeriodUnit: .week)
        XCTAssertEqual(text, "$4.99 for 3 months, then $1.99/week")
    }

    func testPayAsYouGo() {
        let text = IntroOffer.describe(paymentMode: .payAsYouGo,
                                       periodUnit: .month,
                                       periodValue: 3,
                                       offerDisplayPrice: "$0.99",
                                       standardDisplayPrice: "$59.99",
                                       standardPeriodUnit: .year)
        XCTAssertEqual(text, "$0.99/month for 3 months, then $59.99/year")
    }

    func testUnitPluralization() {
        XCTAssertEqual(IntroOffer.unitName(.week, value: 1), "week")
        XCTAssertEqual(IntroOffer.unitName(.week, value: 2), "weeks")
        XCTAssertEqual(IntroOffer.unitName(.month, value: 6), "months")
    }
}

// MARK: - Configuration & bundled resources

final class PaywallConfigurationTests: XCTestCase {

    func testBulletsHelperUsesDefaultIcon() {
        let features = PaywallConfiguration.Feature.bullets(["A", "B"])
        XCTAssertEqual(features.map(\.text), ["A", "B"])
        XCTAssertTrue(features.allSatisfy { $0.systemImage == "checkmark.circle.fill" })
    }

    func testConfigurationDefaults() {
        let config = PaywallConfiguration(headline: "Go Pro")
        XCTAssertTrue(config.showsRestore)
        XCTAssertTrue(config.showsManageSubscription)
        XCTAssertNil(config.subheadline)
        XCTAssertTrue(config.features.isEmpty)
    }

    func testBundledStoreKitConfigurationExists() throws {
        let url = try XCTUnwrap(StoreKitConfiguration.sampleURL,
                                "Configuration.storekit should be bundled as a resource")
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["subscriptionGroups"], "Sample config should define a subscription group")
    }
}
