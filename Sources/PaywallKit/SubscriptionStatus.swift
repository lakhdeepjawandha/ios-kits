import Foundation
import StoreKit

/// High-level subscription status, derived from StoreKit's renewal state and the active offer.
///
/// This is the app-facing summary you switch on for UI ("You're on a free trial", "Your
/// subscription expired"). The detailed StoreKit value lives on
/// ``SubscriptionManager/subscriptionState``.
public enum SubscriptionState: String, Equatable, Sendable, CaseIterable {
    /// No active subscription was found.
    case notSubscribed
    /// Subscribed and currently within an introductory **free trial** offer.
    case trial
    /// Subscribed and paying the standard price.
    case active
    /// Billing failed but the subscription still grants access during Apple's grace period.
    case inGracePeriod
    /// Billing failed and access has lapsed while Apple retries the charge.
    case inBillingRetry
    /// The subscription lapsed and was not renewed.
    case expired
    /// Access was revoked (e.g. refund or family-sharing removal).
    case revoked

    /// Whether this state currently grants access to paid features.
    ///
    /// `trial`, `active`, and `inGracePeriod` are entitled; everything else is not. Note this
    /// mirrors how StoreKit reports `Transaction.currentEntitlements`, which is the source of truth
    /// behind ``SubscriptionManager/hasPro``.
    public var isEntitled: Bool {
        switch self {
        case .trial, .active, .inGracePeriod:
            return true
        case .notSubscribed, .inBillingRetry, .expired, .revoked:
            return false
        }
    }

    /// Map a renewal state plus a trial flag to a ``SubscriptionState``.
    ///
    /// Pure and dependency-free so the mapping can be unit-tested without a StoreKit session.
    ///
    /// - Parameters:
    ///   - renewal: The subscription's renewal state.
    ///   - isInTrial: Whether the active transaction is redeeming an introductory free trial.
    static func resolve(renewal: RawRenewalState, isInTrial: Bool) -> SubscriptionState {
        switch renewal {
        case .subscribed:           return isInTrial ? .trial : .active
        case .inGracePeriod:        return .inGracePeriod
        case .inBillingRetryPeriod: return .inBillingRetry
        case .expired:              return .expired
        case .revoked:              return .revoked
        case .unknown:              return .notSubscribed
        }
    }
}

/// Picks the most representative status from a subscription group: prefer an entitling state
/// (subscribed / grace period), then billing retry, then whatever exists.
///
/// Shared by ``SubscriptionManager`` and ``PurchaseManager`` so both derive ``SubscriptionState``
/// the same way.
func mostRelevantStatus(_ statuses: [Product.SubscriptionInfo.Status]) -> Product.SubscriptionInfo.Status? {
    statuses.first { $0.state == .subscribed || $0.state == .inGracePeriod }
        ?? statuses.first { $0.state == .inBillingRetryPeriod }
        ?? statuses.first
}

/// A StoreKit-independent mirror of `Product.SubscriptionInfo.RenewalState`, so the status-mapping
/// logic stays pure and testable.
enum RawRenewalState: Equatable, Sendable {
    case subscribed
    case expired
    case inBillingRetryPeriod
    case inGracePeriod
    case revoked
    case unknown

    /// Bridge from the StoreKit renewal state.
    init(_ state: Product.SubscriptionInfo.RenewalState) {
        switch state {
        case .subscribed:           self = .subscribed
        case .expired:              self = .expired
        case .inBillingRetryPeriod: self = .inBillingRetryPeriod
        case .inGracePeriod:        self = .inGracePeriod
        case .revoked:              self = .revoked
        default:                    self = .unknown
        }
    }
}

/// Builds a short, human-readable summary of an introductory offer (e.g. a free trial) for display
/// beneath a product's price. Pure so it can be unit-tested without a `Product`.
enum IntroOffer {
    /// Lower-cased name of a subscription period unit, singular or pluralized for `value`.
    static func unitName(_ unit: Product.SubscriptionPeriod.Unit, value: Int) -> String {
        let singular: String
        switch unit {
        case .day:   singular = "day"
        case .week:  singular = "week"
        case .month: singular = "month"
        case .year:  singular = "year"
        @unknown default: singular = "period"
        }
        return value == 1 ? singular : "\(singular)s"
    }

    /// Compose the offer description.
    ///
    /// - Parameters:
    ///   - paymentMode: The offer's payment mode (`.freeTrial`, `.payUpFront`, `.payAsYouGo`).
    ///   - periodUnit: Unit of the offer's billing period.
    ///   - periodValue: Length/count of the offer period.
    ///   - offerDisplayPrice: Localized price of the offer (ignored for a free trial).
    ///   - standardDisplayPrice: Localized standard price charged after the offer ends.
    ///   - standardPeriodUnit: Unit of the standard recurring period.
    /// - Returns: A one-line summary such as `"1-week free trial, then $1.99/week"`.
    static func describe(paymentMode: Product.SubscriptionOffer.PaymentMode,
                         periodUnit: Product.SubscriptionPeriod.Unit,
                         periodValue: Int,
                         offerDisplayPrice: String,
                         standardDisplayPrice: String,
                         standardPeriodUnit: Product.SubscriptionPeriod.Unit) -> String {
        let adjective = unitName(periodUnit, value: 1)           // "week"
        let noun = unitName(periodUnit, value: periodValue)      // "weeks" / "week"
        let perUnit = unitName(standardPeriodUnit, value: 1)     // "week"

        switch paymentMode {
        case .freeTrial:
            return "\(periodValue)-\(adjective) free trial, then \(standardDisplayPrice)/\(perUnit)"
        case .payUpFront:
            return "\(offerDisplayPrice) for \(periodValue) \(noun), then \(standardDisplayPrice)/\(perUnit)"
        case .payAsYouGo:
            return "\(offerDisplayPrice)/\(adjective) for \(periodValue) \(noun), then \(standardDisplayPrice)/\(perUnit)"
        default:
            return "Special introductory offer"
        }
    }
}

/// Locates the bundled sample StoreKit configuration shipped with PaywallKit.
///
/// ## Testing the paywall in the simulator — no paid account required
/// PaywallKit bundles a ready-made `Configuration.storekit` describing four products spanning
/// every StoreKit product type: the subscriptions `pro.weekly` (with a **1-week free trial**) and
/// `pro.yearly`, the non-consumable `pro.lifetime`, and the consumable `credits.10`. To exercise
/// the paywall locally:
///
/// 1. Drag `Configuration.storekit` into your app target (or reference this package's copy). You
///    can read its contents at runtime via ``sampleURL``.
/// 2. In Xcode, open **Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Options** and set
///    **StoreKit Configuration** to `Configuration.storekit`.
/// 3. Run in the simulator. `Product.products(for:)` now returns the sample products and
///    `purchase(_:)` completes against the local StoreKit environment — no App Store Connect
///    setup and no paid Apple Developer account needed.
///
/// For automated tests, drive the same file through `StoreKitTest`'s `SKTestSession`.
public enum StoreKitConfiguration {
    /// File name (without extension) of the bundled configuration.
    public static let name = "Configuration"

    /// URL of the bundled sample `Configuration.storekit`, or `nil` if it could not be located.
    public static var sampleURL: URL? {
        Bundle.module.url(forResource: name, withExtension: "storekit")
    }
}
