import Foundation

/// A charge to be processed by a payment backend.
///
/// `tokenData` carries the Apple Pay payment token (`PKPaymentToken.paymentData`) when the charge
/// originates from Apple Pay; it is `nil` for mock/sandbox flows. A real ``PaymentProcessor`` forwards
/// this token to Stripe/Adyen/etc. for the actual money movement.
public struct ProcessorChargeRequest: Sendable, Equatable {
    /// Amount in minor units (e.g. cents).
    public let amountMinorUnits: Int
    /// ISO 4217 currency code.
    public let currencyCode: String
    /// Order reference.
    public let reference: String
    /// Opaque payment-token bytes (Apple Pay), or `nil`.
    public let tokenData: Data?

    /// Create a charge request.
    public init(amountMinorUnits: Int, currencyCode: String, reference: String, tokenData: Data? = nil) {
        self.amountMinorUnits = amountMinorUnits
        self.currencyCode = currencyCode
        self.reference = reference
        self.tokenData = tokenData
    }
}

/// The swap seam for a real payment backend.
///
/// Apple Pay and Tap to Pay only *authorize* a payment and hand you a token; the actual charge is
/// performed by your processor. Implement this protocol to call Stripe, Adyen, Braintree, or your
/// own server with ``ProcessorChargeRequest/tokenData``, and inject it into ``ApplePayService`` /
/// Tap to Pay. Use ``MockPaymentProcessor`` until that integration exists.
public protocol PaymentProcessor: Sendable {
    /// Process a charge and return the result.
    func process(_ request: ProcessorChargeRequest) async throws -> PaymentResult
}

/// A processor that always approves, for building and demoing flows without a backend.
public struct MockPaymentProcessor: PaymentProcessor {
    /// Whether to approve charges. Default `true`.
    public let approves: Bool
    /// Artificial delay to mimic a network round-trip, in seconds. Default `0`.
    public let simulatedDelay: Double

    /// Create a mock processor.
    public init(approves: Bool = true, simulatedDelay: Double = 0) {
        self.approves = approves
        self.simulatedDelay = simulatedDelay
    }

    public func process(_ request: ProcessorChargeRequest) async throws -> PaymentResult {
        if simulatedDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }
        guard approves else { throw PaymentError.processorFailed("Mock declined the charge.") }
        return PaymentResult(success: true, reference: request.reference)
    }
}
