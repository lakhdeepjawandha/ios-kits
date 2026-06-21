import Foundation

/// A tiny persistent ledger for consumable credits, backed by `UserDefaults`.
///
/// Use it to track an in-app credit/coin balance that the user tops up by buying consumable
/// products and spends on features. Backed by Foundation only — no external persistence layer.
///
/// ```swift
/// let ledger = CreditsLedger()
/// ledger.grant(10)           // bought "credits.10"
/// ledger.balance             // 10
/// ledger.spend(3)            // true; balance is now 7
/// ledger.spend(100)          // false; insufficient, balance unchanged
/// ```
public final class CreditsLedger: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    /// Creates a ledger.
    /// - Parameters:
    ///   - defaults: The `UserDefaults` suite backing the balance. Defaults to `.standard`; inject
    ///     an ephemeral suite in tests.
    ///   - key: The storage key for the balance. Defaults to `"paywallkit.credits.balance"`.
    public init(
        defaults: UserDefaults = .standard,
        key: String = "paywallkit.credits.balance"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// The current credit balance. Never negative.
    public var balance: Int {
        max(0, defaults.integer(forKey: key))
    }

    /// Adds credits to the balance.
    ///
    /// Non-positive amounts are ignored.
    /// - Parameter amount: The number of credits to add.
    public func grant(_ amount: Int) {
        guard amount > 0 else { return }
        defaults.set(balance + amount, forKey: key)
    }

    /// Attempts to deduct credits from the balance.
    ///
    /// - Parameter amount: The number of credits to spend.
    /// - Returns: `true` if the balance covered the amount and was deducted; `false` if `amount`
    ///   is non-positive or exceeds the current balance (in which case the balance is unchanged).
    @discardableResult
    public func spend(_ amount: Int) -> Bool {
        guard amount > 0, balance >= amount else { return false }
        defaults.set(balance - amount, forKey: key)
        return true
    }

    /// Resets the balance to zero by clearing the stored value.
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
