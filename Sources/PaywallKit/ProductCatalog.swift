import StoreKit

// MARK: - Product kind

/// A StoreKit-independent classification of `Product.ProductType`.
///
/// Mirroring the product type as a plain enum keeps the entitlement-mapping logic pure and
/// unit-testable without a StoreKit session.
public enum ProductKind: String, Equatable, Sendable, CaseIterable {
    /// A one-time purchase that is consumed and can be bought again (e.g. credits).
    case consumable
    /// A one-time purchase that grants a permanent, restorable entitlement (e.g. a lifetime unlock).
    case nonConsumable
    /// An auto-renewing subscription.
    case autoRenewable
    /// A non-renewing subscription (fixed-duration access that does not auto-renew).
    case nonRenewable

    /// Bridges from the StoreKit product type.
    ///
    /// Unrecognised future types map to ``nonConsumable`` so they are treated as a durable
    /// entitlement rather than silently dropped.
    /// - Parameter type: The StoreKit `Product.ProductType`.
    public init(_ type: Product.ProductType) {
        switch type {
        case .consumable:    self = .consumable
        case .nonConsumable: self = .nonConsumable
        case .autoRenewable: self = .autoRenewable
        case .nonRenewable:  self = .nonRenewable
        default:             self = .nonConsumable
        }
    }

    /// Whether a purchase of this kind yields a persistent entitlement that appears in
    /// `Transaction.currentEntitlements` and can be restored.
    ///
    /// Non-consumables and both subscription kinds are restorable; consumables are not — they
    /// are applied once at purchase time (see ``CreditsLedger``).
    public var grantsRestorableEntitlement: Bool {
        switch self {
        case .nonConsumable, .autoRenewable, .nonRenewable:
            return true
        case .consumable:
            return false
        }
    }
}

// MARK: - Purchase effect

/// The effect a verified purchase has on local state.
///
/// Pure and value-typed so the mapping from product kind to outcome can be unit-tested without
/// touching StoreKit.
public enum PurchaseEffect: Equatable, Sendable {
    /// A durable entitlement keyed by product identifier (non-consumable or subscription).
    case entitlement(productID: String)
    /// A consumable purchase that grants `amount` credits to the ``CreditsLedger``.
    case credits(productID: String, amount: Int)
}

public extension ProductKind {
    /// Resolves how a purchase of a product of this kind should be applied.
    ///
    /// - Parameters:
    ///   - productID: The purchased product's identifier.
    ///   - creditValues: A map of consumable product id → credit amount granted. Missing entries
    ///     grant `0`.
    /// - Returns: Either an ``PurchaseEffect/entitlement(productID:)`` for durable purchases or
    ///   ``PurchaseEffect/credits(productID:amount:)`` for consumables.
    func effect(productID: String, creditValues: [String: Int]) -> PurchaseEffect {
        switch self {
        case .consumable:
            return .credits(productID: productID, amount: creditValues[productID] ?? 0)
        case .nonConsumable, .autoRenewable, .nonRenewable:
            return .entitlement(productID: productID)
        }
    }
}
