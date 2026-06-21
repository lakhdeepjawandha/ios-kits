import Foundation

/// Accepts contactless payments using **Tap to Pay on iPhone** (Apple's `ProximityReader`).
///
/// ## Entitlements & setup (real Tap to Pay)
/// Tap to Pay on iPhone requires a **paid Apple Developer account** and:
/// - The **Tap to Pay on iPhone** entitlement
///   `com.apple.developer.proximity-reader.payment.acceptance`, which Apple grants on request.
/// - A supported device/region and a payment service provider that issues the **merchant token**
///   used to configure the reader.
///
/// Apps without the entitlement should use ``MockTapToPayService`` so flows build and demo. The real
/// ``ProximityReaderTapToPayService`` is compiled only where `ProximityReader` is available (iOS).
public protocol TapToPayService: Sendable {
    /// Whether Tap to Pay on iPhone is supported on this device.
    var isSupported: Bool { get }

    /// Perform one-time merchant/account linking (prompts the user the first time).
    func linkAccount() async throws

    /// Collect a contactless payment for the cart.
    func collectPayment(for cart: PaymentCart) async throws -> PaymentResult
}

/// A sandbox Tap to Pay implementation that "succeeds" without hardware or entitlements.
public struct MockTapToPayService: TapToPayService {
    /// Whether ``isSupported`` reports support. Default `true`.
    public let supported: Bool
    /// Whether ``collectPayment(for:)`` approves. Default `true`.
    public let approves: Bool

    /// Create a mock.
    public init(supported: Bool = true, approves: Bool = true) {
        self.supported = supported
        self.approves = approves
    }

    public var isSupported: Bool { supported }

    public func linkAccount() async throws {
        guard supported else { throw PaymentError.tapToPayUnsupported }
    }

    public func collectPayment(for cart: PaymentCart) async throws -> PaymentResult {
        guard supported else { throw PaymentError.tapToPayUnsupported }
        guard !cart.lineItems.isEmpty else { throw PaymentError.invalidCart }
        guard approves else { throw PaymentError.authorizationFailed }
        return PaymentResult(success: true, reference: cart.reference)
    }
}

#if canImport(ProximityReader)
import ProximityReader

/// Real Tap to Pay on iPhone via `ProximityReader`.
///
/// Availability is checked through `PaymentCardReader.isSupported`. Completing a transaction
/// additionally requires a **merchant token** from your payment service provider and the
/// `com.apple.developer.proximity-reader.payment.acceptance` entitlement; until those are wired up,
/// ``collectPayment(for:)`` throws ``PaymentError/notConfigured(_:)`` so the type still builds and
/// the seam is explicit.
@available(iOS 16.4, *)
public struct ProximityReaderTapToPayService: TapToPayService {
    /// The backend that finalizes the charge from the reader's result.
    public let processor: PaymentProcessor

    /// Create the service.
    public init(processor: PaymentProcessor = MockPaymentProcessor()) {
        self.processor = processor
    }

    public var isSupported: Bool { PaymentCardReader.isSupported }

    public func linkAccount() async throws {
        guard isSupported else { throw PaymentError.tapToPayUnsupported }
        // A real implementation fetches a `PaymentCardReader.Token` from your PSP and calls
        // `PaymentCardReader.prepare(using:)`. That requires the acceptance entitlement.
        throw PaymentError.notConfigured(
            "Provide a PaymentCardReader.Token from your payment service provider and the "
            + "com.apple.developer.proximity-reader.payment.acceptance entitlement.")
    }

    public func collectPayment(for cart: PaymentCart) async throws -> PaymentResult {
        guard isSupported else { throw PaymentError.tapToPayUnsupported }
        guard !cart.lineItems.isEmpty else { throw PaymentError.invalidCart }
        // A real implementation creates a `PaymentCardReaderSession`, reads the card, and forwards
        // the result to `processor`. That path needs the acceptance entitlement and a merchant token.
        throw PaymentError.entitlementRequired("com.apple.developer.proximity-reader.payment.acceptance")
    }
}
#endif
