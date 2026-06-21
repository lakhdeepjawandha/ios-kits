import StoreKit
import Observation
import OSLog
import AppFoundation

public enum StoreError: Error { case failedVerification }

/// StoreKit 2 subscription manager.
///
/// Loads your products, tracks entitlements, and exposes a high-level ``subscriptionState``
/// (trial / active / expired / …) derived from `Product.SubscriptionInfo` and its renewal state.
/// Observe it from SwiftUI; gate content with ``PaywallKit/SwiftUI/View/requiresPro(_:onLocked:)``
/// and present ``PaywallView`` to sell.
///
/// ## Local testing — no paid account required
/// Test against the bundled sample StoreKit configuration (see ``StoreKitConfiguration``): select
/// `Configuration.storekit` under **Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration** and run
/// in the simulator. No App Store Connect setup and no paid Apple Developer account are needed
/// until you ship.
@MainActor
@Observable
public final class SubscriptionManager {
    /// Loaded products, in the order requested.
    public private(set) var products: [Product] = []
    /// Product IDs the user is currently entitled to (from `Transaction.currentEntitlements`).
    public private(set) var purchasedProductIDs: Set<String> = []
    /// High-level subscription status across the subscription group. Defaults to
    /// ``SubscriptionState/notSubscribed`` until ``load()`` runs.
    public private(set) var subscriptionState: SubscriptionState = .notSubscribed
    /// Product IDs for which the user is currently eligible to redeem an introductory offer.
    public private(set) var introEligibleProductIDs: Set<String> = []

    /// Whether the user has any active entitlement (the simplest "is this user Pro?" check).
    public var hasPro: Bool { !purchasedProductIDs.isEmpty }

    @ObservationIgnored private let productIDs: [String]
    @ObservationIgnored nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    /// Create a manager for the given product identifiers and begin observing transaction updates.
    ///
    /// - Parameter productIDs: The subscription product identifiers to manage.
    public init(productIDs: [String]) {
        self.productIDs = productIDs
        updatesTask = observeTransactionUpdates()
    }

    nonisolated deinit { updatesTask?.cancel() }

    /// Fetch products from StoreKit and refresh entitlement, status, and intro-offer eligibility.
    public func load() async {
        do {
            products = try await Product.products(for: productIDs)
            await refreshPurchased()
        } catch {
            Logger.app("PaywallKit").error("Load failed: \(error.localizedDescription)")
        }
    }

    /// Purchase a product. Returns `true` when the purchase succeeds and is verified.
    ///
    /// - Parameter product: The product to buy.
    /// - Returns: `true` on a verified success; `false` for user-cancelled or pending results.
    /// - Throws: ``StoreError/failedVerification`` if StoreKit returns an unverified transaction.
    @discardableResult
    public func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verify(verification)
            await refreshPurchased()
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Restore purchases by syncing with the App Store, then refresh entitlement state.
    public func restore() async {
        try? await AppStore.sync()
        await refreshPurchased()
    }

    /// Re-read current entitlements and recompute ``subscriptionState`` and
    /// ``introEligibleProductIDs``.
    public func refreshPurchased() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if let transaction = try? verify(result) { ids.insert(transaction.productID) }
        }
        purchasedProductIDs = ids
        await updateSubscriptionState()
        await updateIntroEligibility()
    }

    // MARK: - Subscription status

    /// Whether the user can currently redeem an introductory offer (e.g. a free trial) for the
    /// given product. Returns `false` for non-subscription products.
    ///
    /// Eligibility is determined by StoreKit per subscription group: a user who has previously used
    /// an introductory offer in the group is no longer eligible.
    ///
    /// - Parameter product: The subscription product to check.
    /// - Returns: `true` if an introductory offer can be redeemed.
    public func isEligibleForIntroOffer(_ product: Product) async -> Bool {
        guard let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    /// A short, human-readable description of a product's introductory offer, suitable for display
    /// beneath its price (e.g. `"1-week free trial, then $1.99/week"`).
    ///
    /// - Parameter product: The subscription product.
    /// - Returns: The offer summary, or `nil` if the product has no introductory offer.
    public func introOfferDescription(for product: Product) -> String? {
        guard let subscription = product.subscription,
              let offer = subscription.introductoryOffer else { return nil }
        return IntroOffer.describe(paymentMode: offer.paymentMode,
                                   periodUnit: offer.period.unit,
                                   periodValue: offer.period.value,
                                   offerDisplayPrice: offer.displayPrice,
                                   standardDisplayPrice: product.displayPrice,
                                   standardPeriodUnit: subscription.subscriptionPeriod.unit)
    }

    private func updateSubscriptionState() async {
        guard let subscription = products.compactMap({ $0.subscription }).first else {
            // No subscription products loaded — fall back to entitlement presence.
            subscriptionState = hasPro ? .active : .notSubscribed
            return
        }
        do {
            let statuses = try await subscription.status
            guard let status = Self.mostRelevant(statuses) else {
                subscriptionState = .notSubscribed
                return
            }
            let renewal = RawRenewalState(status.state)
            let inTrial = isIntroductoryTrial(status.transaction)
            subscriptionState = SubscriptionState.resolve(renewal: renewal, isInTrial: inTrial)
        } catch {
            Logger.app("PaywallKit").error("Status refresh failed: \(error.localizedDescription)")
        }
    }

    private func updateIntroEligibility() async {
        var eligible = Set<String>()
        for product in products where await isEligibleForIntroOffer(product) {
            eligible.insert(product.id)
        }
        introEligibleProductIDs = eligible
    }

    /// Pick the most representative status from a subscription group: prefer an entitling state
    /// (subscribed / grace period), then billing retry, then whatever exists.
    private static func mostRelevant(_ statuses: [Product.SubscriptionInfo.Status]) -> Product.SubscriptionInfo.Status? {
        statuses.first { $0.state == .subscribed || $0.state == .inGracePeriod }
            ?? statuses.first { $0.state == .inBillingRetryPeriod }
            ?? statuses.first
    }

    /// Whether a verified transaction is redeeming an introductory offer (treated as a trial).
    ///
    /// - Note: Uses the `Transaction.offer` API (iOS 17.2+/macOS 14.2+). On earlier 17.x point
    ///   releases the offer kind is unavailable here, so the state resolves to `.active` rather
    ///   than `.trial`; entitlement is unaffected.
    private func isIntroductoryTrial(_ verification: VerificationResult<Transaction>) -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        if #available(iOS 17.2, macOS 14.2, *) {
            return transaction.offer?.type == .introductory
        }
        return false
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.failedVerification
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshPurchased()
            }
        }
    }
}
