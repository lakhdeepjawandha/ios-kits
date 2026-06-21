import Foundation

/// Errors surfaced by PaymentsKit flows.
public enum PaymentError: Error, Equatable {
    /// Apple Pay is unavailable (no eligible cards, restricted, or unsupported device).
    case applePayUnavailable
    /// The user cancelled the payment sheet.
    case userCancelled
    /// Payment authorization failed.
    case authorizationFailed
    /// Tap to Pay on iPhone isn't supported on this device/region.
    case tapToPayUnsupported
    /// A required entitlement is missing. Carries the entitlement identifier.
    case entitlementRequired(String)
    /// The feature needs additional configuration (merchant token, certificates, etc.).
    case notConfigured(String)
    /// The payment processor (Stripe/Adyen/…) rejected the charge. Carries a message.
    case processorFailed(String)
    /// The cart is empty or otherwise invalid.
    case invalidCart
    /// The Wallet pass payload could not be encoded.
    case passEncodingFailed
}

extension PaymentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .applePayUnavailable:        return "Apple Pay is not available on this device."
        case .userCancelled:              return "The payment was cancelled."
        case .authorizationFailed:        return "Payment authorization failed."
        case .tapToPayUnsupported:        return "Tap to Pay on iPhone is not supported here."
        case let .entitlementRequired(e): return "Missing required entitlement: \(e)"
        case let .notConfigured(m):       return "Not configured: \(m)"
        case let .processorFailed(m):     return "Payment processor error: \(m)"
        case .invalidCart:                return "The cart is empty or invalid."
        case .passEncodingFailed:         return "Failed to encode the Wallet pass."
        }
    }
}
