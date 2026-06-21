import StoreKit
import Observation
import OSLog
import AppFoundation

/// StoreKit 2 manager covering **all** product types: auto-renewing subscriptions,
/// non-consumables (e.g. a lifetime unlock), and consumables (e.g. credits).
///
/// It is the generalised counterpart to ``SubscriptionManager`` (which remains available for
/// subscription-only apps):
/// - Durable purchases — non-consumables and active subscriptions — are tracked in
///   ``entitledProductIDs``, rebuilt from `Transaction.currentEntitlements` and restorable via
///   ``restore()``.
/// - Subscription status is summarised in ``subscriptionState``.
/// - Consumable purchases top up a ``CreditsLedger``; read ``creditBalance`` and spend with
///   ``spendCredits(_:)``.
///
/// ## Local testing — no paid account required
/// Drive it against the bundled ``StoreKitConfiguration`` sample, which includes `pro.weekly`,
/// `pro.yearly`, a non-consumable `pro.lifetime`, and a consumable `credits.10`.
@MainActor
@Observable
public final class PurchaseManager {
    /// Loaded products, in the order requested.
    public private(set) var products: [Product] = []
    /// Product IDs the user durably owns: non-consumables plus active subscriptions, from
    /// `Transaction.currentEntitlements`. Consumables never appear here.
    public private(set) var entitledProductIDs: Set<String> = []
    /// High-level subscription status across the subscription group. Defaults to
    /// ``SubscriptionState/notSubscribed`` until ``load()`` runs.
    public private(set) var subscriptionState: SubscriptionState = .notSubscribed

    /// The persistent consumable credit balance.
    public var creditBalance: Int { ledger.balance }

    /// Whether the user holds any durable entitlement (an owned non-consumable or active
    /// subscription).
    public var hasEntitlement: Bool { !entitledProductIDs.isEmpty }

    /// The ledger backing the consumable ``creditBalance``. Exposes `grant`/`spend`/`balance`.
    @ObservationIgnored public let ledger: CreditsLedger

    @ObservationIgnored private let productIDs: [String]
    @ObservationIgnored private let creditValues: [String: Int]
    @ObservationIgnored nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    /// Creates a manager for the given product identifiers and begins observing transaction updates.
    ///
    /// - Parameters:
    ///   - productIDs: All product identifiers to manage, of any type.
    ///   - creditValues: A map of consumable product id → credits granted per purchase
    ///     (e.g. `["credits.10": 10]`). Defaults to empty.
    ///   - ledger: The credit ledger to use. Defaults to a `.standard`-backed ``CreditsLedger``.
    public init(
        productIDs: [String],
        creditValues: [String: Int] = [:],
        ledger: CreditsLedger = CreditsLedger()
    ) {
        self.productIDs = productIDs
        self.creditValues = creditValues
        self.ledger = ledger
        updatesTask = observeTransactionUpdates()
    }

    nonisolated deinit { updatesTask?.cancel() }

    /// Fetch products from StoreKit and refresh entitlement and subscription state.
    public func load() async {
        do {
            products = try await Product.products(for: productIDs)
            await refreshEntitlements()
        } catch {
            Logger.app("PaywallKit").error("Load failed: \(error.localizedDescription)")
        }
    }

    /// Purchase a product of any type.
    ///
    /// On a verified success, consumables credit the ``ledger`` and durable purchases refresh
    /// ``entitledProductIDs``; the transaction is then finished.
    ///
    /// - Parameter product: The product to buy.
    /// - Returns: `true` on a verified success; `false` for user-cancelled or pending results.
    /// - Throws: ``StoreError/failedVerification`` if StoreKit returns an unverified transaction.
    @discardableResult
    public func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.verify(verification)
            apply(transaction)
            await refreshEntitlements()
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Applies a verified transaction's consumable effect (crediting the ledger). Durable
    /// entitlements are picked up by ``refreshEntitlements()`` instead.
    private func apply(_ transaction: Transaction) {
        let kind = ProductKind(transaction.productType)
        if case let .credits(_, amount) = kind.effect(productID: transaction.productID,
                                                       creditValues: creditValues) {
            ledger.grant(amount)
        }
    }

    /// Restore durable purchases — non-consumables and subscriptions — by syncing with the App
    /// Store, then refresh entitlement state.
    ///
    /// Consumables are intentionally not restored: they are spent balances, not entitlements.
    public func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Re-read current entitlements and recompute ``entitledProductIDs`` and ``subscriptionState``.
    public func refreshEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.verify(result) { ids.insert(transaction.productID) }
        }
        entitledProductIDs = ids
        await updateSubscriptionState()
    }

    /// Whether the user is currently entitled to the given product id (owned non-consumable or
    /// active subscription).
    /// - Parameter productID: The product identifier to check.
    public func isEntitled(to productID: String) -> Bool {
        entitledProductIDs.contains(productID)
    }

    // MARK: - Credits

    /// Grants credits directly to the ledger (e.g. a promotional top-up).
    /// - Parameter amount: The number of credits to add.
    public func grantCredits(_ amount: Int) {
        ledger.grant(amount)
    }

    /// Attempts to spend credits from the ledger.
    /// - Parameter amount: The number of credits to spend.
    /// - Returns: `true` if the balance covered the amount; `false` otherwise.
    @discardableResult
    public func spendCredits(_ amount: Int) -> Bool {
        ledger.spend(amount)
    }

    // MARK: - Subscription status

    private func updateSubscriptionState() async {
        guard let subscription = products.compactMap({ $0.subscription }).first else {
            // No subscription products loaded — subscription status is simply "not subscribed".
            // Durable non-consumable ownership is reflected by ``entitledProductIDs`` instead.
            subscriptionState = .notSubscribed
            return
        }
        do {
            let statuses = try await subscription.status
            guard let status = mostRelevantStatus(statuses) else {
                subscriptionState = .notSubscribed
                return
            }
            let renewal = RawRenewalState(status.state)
            let inTrial = Self.isIntroductoryTrial(status.transaction)
            subscriptionState = SubscriptionState.resolve(renewal: renewal, isInTrial: inTrial)
        } catch {
            Logger.app("PaywallKit").error("Status refresh failed: \(error.localizedDescription)")
        }
    }

    /// Whether a verified transaction is redeeming an introductory offer (treated as a trial).
    private static func isIntroductoryTrial(_ verification: VerificationResult<Transaction>) -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        if #available(iOS 17.2, macOS 14.2, *) {
            return transaction.offer?.type == .introductory
        }
        return false
    }

    private static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.failedVerification
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlements()
            }
        }
    }
}
