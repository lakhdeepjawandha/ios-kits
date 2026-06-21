import Foundation

/// A monetary amount stored in **minor units** (e.g. cents) to avoid floating-point rounding.
///
/// - Note: Conversion to a decimal amount assumes a 2-decimal currency (the common case). For
///   zero-decimal currencies (e.g. JPY) or three-decimal currencies, adjust before display.
public struct Money: Equatable, Sendable {
    /// The amount in minor units (e.g. `1299` = `$12.99`).
    public let minorUnits: Int
    /// ISO 4217 currency code (e.g. `"AUD"`).
    public let currencyCode: String

    /// Create a money value.
    public init(minorUnits: Int, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    /// The amount as an exact `Decimal` (minor units ÷ 100).
    public var amount: Decimal { Decimal(minorUnits) / 100 }

    /// The amount as an `NSDecimalNumber`, for PassKit summary items.
    public var nsDecimalAmount: NSDecimalNumber { NSDecimalNumber(decimal: amount) }
}

/// A single labelled line in a ``PaymentCart``.
public struct LineItem: Equatable, Sendable {
    /// Human-readable label (e.g. `"Flat White"`).
    public let label: String
    /// The item's price.
    public let amount: Money

    /// Create a line item.
    public init(label: String, amount: Money) {
        self.label = label
        self.amount = amount
    }
}

/// A cart of line items in a single currency, ready to be turned into an Apple Pay request or a
/// Tap to Pay collection. Pure and `Equatable` so totals and summaries are unit-testable.
public struct PaymentCart: Equatable, Sendable {
    /// The line items.
    public var lineItems: [LineItem]
    /// ISO 4217 currency code for the whole cart.
    public var currencyCode: String
    /// Merchant/display name shown on the grand-total line.
    public var merchantName: String
    /// An order reference passed through to the processor.
    public var reference: String

    /// Create a cart.
    ///
    /// - Parameters:
    ///   - lineItems: The items.
    ///   - currencyCode: ISO 4217 currency code.
    ///   - merchantName: Name shown on the total line.
    ///   - reference: Order reference for the processor. Default empty.
    public init(lineItems: [LineItem], currencyCode: String, merchantName: String, reference: String = "") {
        self.lineItems = lineItems
        self.currencyCode = currencyCode
        self.merchantName = merchantName
        self.reference = reference
    }

    /// The grand total (sum of all line items), in the cart currency.
    public var total: Money {
        Money(minorUnits: lineItems.reduce(0) { $0 + $1.amount.minorUnits }, currencyCode: currencyCode)
    }
}
