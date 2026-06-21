import StoreKit
import Observation
import OSLog
import AppFoundation

public enum StoreError: Error { case failedVerification }

/// StoreKit 2 subscription manager. Test locally with a `.storekit` configuration file —
/// no paid Apple Developer account required until you ship.
@MainActor
@Observable
public final class SubscriptionManager {
    public private(set) var products: [Product] = []
    public private(set) var purchasedProductIDs: Set<String> = []
    public var hasPro: Bool { !purchasedProductIDs.isEmpty }

    private let productIDs: [String]
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    public init(productIDs: [String]) {
        self.productIDs = productIDs
        updatesTask = observeTransactionUpdates()
    }

    nonisolated deinit { updatesTask?.cancel() }

    public func load() async {
        do {
            products = try await Product.products(for: productIDs)
            await refreshPurchased()
        } catch {
            Logger.app("PaywallKit").error("Load failed: \(error.localizedDescription)")
        }
    }

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

    public func restore() async {
        try? await AppStore.sync()
        await refreshPurchased()
    }

    public func refreshPurchased() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if let transaction = try? verify(result) { ids.insert(transaction.productID) }
        }
        purchasedProductIDs = ids
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

