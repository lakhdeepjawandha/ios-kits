import Foundation
import PassKit

/// Configuration for an Apple Pay request.
///
/// ## Entitlements & setup (real Apple Pay)
/// Running Apple Pay on a device requires a **paid Apple Developer account** and:
/// - A **Merchant ID** created in the developer portal (`merchant.<your.bundle>`).
/// - The **Apple Pay** capability, which adds the `com.apple.developer.in-app-payments`
///   entitlement listing your Merchant ID(s).
/// - A payment-processing certificate associated with the Merchant ID (configured with your
///   processor — Stripe/Adyen/etc.).
///
/// Without these, ``ApplePayService/canMakePayments()`` returns `false`; use ``MockApplePayService``
/// to build and demo in the sandbox.
public struct ApplePayConfiguration: Sendable {
    /// Your Merchant ID (`merchant.com.example`).
    public var merchantIdentifier: String
    /// ISO 3166-1 alpha-2 country code of the merchant (e.g. `"AU"`).
    public var countryCode: String
    /// Card networks you accept.
    public var supportedNetworks: [PKPaymentNetwork]
    /// Merchant capabilities (3-D Secure is required for most processors).
    public var merchantCapabilities: PKMerchantCapability

    /// Create a configuration.
    ///
    /// - Parameters:
    ///   - merchantIdentifier: Your Merchant ID.
    ///   - countryCode: Merchant country code.
    ///   - supportedNetworks: Accepted networks. Default Visa/Mastercard/Amex.
    ///   - merchantCapabilities: Capabilities. Default `.threeDSecure`.
    public init(merchantIdentifier: String,
                countryCode: String,
                supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex],
                merchantCapabilities: PKMerchantCapability = .threeDSecure) {
        self.merchantIdentifier = merchantIdentifier
        self.countryCode = countryCode
        self.supportedNetworks = supportedNetworks
        self.merchantCapabilities = merchantCapabilities
    }
}

/// Builds a `PKPaymentRequest` from a configuration and cart. Pure and unit-tested (no hardware).
public enum ApplePayRequestBuilder {
    /// Compose a payment request.
    ///
    /// - Parameters:
    ///   - configuration: Merchant configuration.
    ///   - cart: The cart to charge. Its currency overrides the request currency; line items plus a
    ///     final total become the `paymentSummaryItems`.
    /// - Returns: A configured `PKPaymentRequest`.
    public static func makeRequest(configuration: ApplePayConfiguration, cart: PaymentCart) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = configuration.merchantIdentifier
        request.countryCode = configuration.countryCode
        request.currencyCode = cart.currencyCode
        request.supportedNetworks = configuration.supportedNetworks
        request.merchantCapabilities = configuration.merchantCapabilities
        request.paymentSummaryItems = summaryItems(for: cart)
        return request
    }

    /// The summary items for a cart: one per line item, plus a `.final` grand-total line.
    public static func summaryItems(for cart: PaymentCart) -> [PKPaymentSummaryItem] {
        var items = cart.lineItems.map {
            PKPaymentSummaryItem(label: $0.label, amount: $0.amount.nsDecimalAmount, type: .final)
        }
        items.append(PKPaymentSummaryItem(label: cart.merchantName,
                                          amount: cart.total.nsDecimalAmount,
                                          type: .final))
        return items
    }
}

/// The outcome of an Apple Pay authorization, independent of PassKit types.
public enum AuthorizationOutcome: Equatable, Sendable {
    case approved
    case declined
    case cancelled
}

/// Maps between processor results and PassKit authorization types. Unit-tested with constructible
/// PassKit values (no hardware).
public enum ApplePayResultMapper {
    /// The `PKPaymentAuthorizationResult` to hand back to the sheet for a processor result.
    public static func authorizationResult(for result: PaymentResult) -> PKPaymentAuthorizationResult {
        PKPaymentAuthorizationResult(status: result.success ? .success : .failure, errors: nil)
    }

    /// Map a PassKit authorization status to a domain ``AuthorizationOutcome``.
    public static func outcome(for status: PKPaymentAuthorizationStatus) -> AuthorizationOutcome {
        switch status {
        case .success: return .approved
        default:       return .declined
        }
    }
}

/// Abstraction over an Apple Pay payer, so apps can depend on a protocol and swap in
/// ``MockApplePayService`` for sandbox builds.
public protocol ApplePayPaying: Sendable {
    /// Whether payments can currently be made.
    func canMakePayments() -> Bool
    /// Present Apple Pay for a cart and return the result.
    func pay(for cart: PaymentCart) async throws -> PaymentResult
}

/// Real Apple Pay via `PKPaymentAuthorizationController`, charging through an injected
/// ``PaymentProcessor``.
///
/// The request building and result mapping are pure (and tested); presentation is iOS-only and
/// requires the entitlements described on ``ApplePayConfiguration``.
public struct ApplePayService: ApplePayPaying {
    /// Merchant configuration.
    public let configuration: ApplePayConfiguration
    /// The backend that performs the actual charge from the Apple Pay token.
    public let processor: PaymentProcessor

    /// Create a service.
    ///
    /// - Parameters:
    ///   - configuration: Merchant configuration.
    ///   - processor: Charge backend. Default ``MockPaymentProcessor``.
    public init(configuration: ApplePayConfiguration, processor: PaymentProcessor = MockPaymentProcessor()) {
        self.configuration = configuration
        self.processor = processor
    }

    /// Whether the device can make payments with the configured networks.
    public func canMakePayments() -> Bool {
        PKPaymentAuthorizationController.canMakePayments()
            && PKPaymentAuthorizationController.canMakePayments(usingNetworks: configuration.supportedNetworks)
    }

    /// Build the `PKPaymentRequest` for a cart (exposed for inspection/testing).
    public func makeRequest(for cart: PaymentCart) -> PKPaymentRequest {
        ApplePayRequestBuilder.makeRequest(configuration: configuration, cart: cart)
    }

    /// Present Apple Pay and charge via the processor.
    ///
    /// - Parameter cart: The cart to charge.
    /// - Returns: The payment result.
    /// - Throws: ``PaymentError/applePayUnavailable`` if payments can't be made,
    ///   ``PaymentError/invalidCart`` for an empty cart, ``PaymentError/userCancelled``, or a
    ///   processor error. On non-iOS platforms throws ``PaymentError/notConfigured(_:)``.
    public func pay(for cart: PaymentCart) async throws -> PaymentResult {
        guard !cart.lineItems.isEmpty else { throw PaymentError.invalidCart }
        guard canMakePayments() else { throw PaymentError.applePayUnavailable }
        #if os(iOS)
        let request = makeRequest(for: cart)
        let presenter = await ApplePayPresenter(processor: processor, cart: cart)
        return try await presenter.present(request: request)
        #else
        throw PaymentError.notConfigured("Apple Pay presentation is available on iOS.")
        #endif
    }
}

/// A sandbox Apple Pay implementation that approves without hardware or a Merchant ID, so apps
/// build and demo before Apple Pay is provisioned.
public struct MockApplePayService: ApplePayPaying {
    /// Whether ``canMakePayments()`` reports availability. Default `true`.
    public let available: Bool
    /// The result returned by ``pay(for:)`` (uses the cart's reference). Default success.
    public let approves: Bool

    /// Create a mock.
    public init(available: Bool = true, approves: Bool = true) {
        self.available = available
        self.approves = approves
    }

    public func canMakePayments() -> Bool { available }

    public func pay(for cart: PaymentCart) async throws -> PaymentResult {
        guard !cart.lineItems.isEmpty else { throw PaymentError.invalidCart }
        guard available else { throw PaymentError.applePayUnavailable }
        guard approves else { throw PaymentError.authorizationFailed }
        return PaymentResult(success: true, reference: cart.reference)
    }
}

#if os(iOS)
/// Bridges the `PKPaymentAuthorizationController` delegate callbacks to an async result.
@MainActor
private final class ApplePayPresenter: NSObject, PKPaymentAuthorizationControllerDelegate {
    private let processor: PaymentProcessor
    private let cart: PaymentCart
    private var continuation: CheckedContinuation<PaymentResult, Error>?
    private var finalResult: PaymentResult?
    private var controller: PKPaymentAuthorizationController?

    init(processor: PaymentProcessor, cart: PaymentCart) {
        self.processor = processor
        self.cart = cart
    }

    func present(request: PKPaymentRequest) async throws -> PaymentResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = PKPaymentAuthorizationController(paymentRequest: request)
            self.controller = controller
            controller.delegate = self
            controller.present { presented in
                if !presented {
                    Task { @MainActor in self.finish(.failure(PaymentError.applePayUnavailable)) }
                }
            }
        }
    }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                        didAuthorizePayment payment: PKPayment,
                                        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        let tokenData = payment.token.paymentData
        let charge = ProcessorChargeRequest(amountMinorUnits: cart.total.minorUnits,
                                            currencyCode: cart.currencyCode,
                                            reference: cart.reference,
                                            tokenData: tokenData)
        Task {
            do {
                let result = try await processor.process(charge)
                await MainActor.run { self.finalResult = result }
                completion(ApplePayResultMapper.authorizationResult(for: result))
            } catch {
                await MainActor.run { self.finalResult = PaymentResult(success: false, reference: self.cart.reference) }
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        if let finalResult {
            finish(.success(finalResult))
        } else {
            finish(.failure(PaymentError.userCancelled))
        }
    }

    private func finish(_ result: Result<PaymentResult, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
#endif
