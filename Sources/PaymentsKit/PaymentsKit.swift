import Foundation

/// Apple Pay, Tap to Pay on iPhone, and PassKit/Wallet passes.
///
/// > Important: Real Apple Pay, Tap to Pay on iPhone, and Wallet passes all require a **paid Apple
/// > Developer account** plus capabilities/entitlements and a device — they do **not** work in the
/// > Simulator or on a free account. Every feature here sits behind a protocol with a working mock
/// > so apps build and demo in the sandbox **without a Merchant ID**.
///
/// ## Entitlements at a glance
/// - **Apple Pay** (``ApplePayService``): the *Apple Pay* capability →
///   `com.apple.developer.in-app-payments` entitlement listing your **Merchant ID**
///   (`merchant.com.example`), plus a payment-processing certificate. Mock: ``MockApplePayService``.
/// - **Tap to Pay on iPhone** (Tap to Pay via `ProximityReader`): the
///   `com.apple.developer.proximity-reader.payment.acceptance` entitlement (granted by Apple on
///   request) and a merchant token from your PSP. Mock: ``MockTapToPayService``.
/// - **Wallet passes** (``WalletPassBuilder``): a **Pass Type ID** + its certificate and the Apple
///   **WWDR** certificate to sign `.pkpass`, and `com.apple.developer.pass-type-identifiers` to add
///   passes. Mock: ``MockWalletPassProvider``.
///
/// ## Topics
/// ### Core
/// - ``Money``
/// - ``LineItem``
/// - ``PaymentCart``
/// - ``PaymentResult``
/// - ``PaymentError``
/// - ``PaymentProcessor``
/// ### Apple Pay
/// - ``ApplePayService``
/// - ``ApplePayConfiguration``
/// - ``ApplePayRequestBuilder``
/// - ``ApplePayResultMapper``
/// - ``MockApplePayService``
/// ### Tap to Pay
/// - ``TapToPayService``
/// - ``MockTapToPayService``
/// ### Wallet
/// - ``WalletPassBuilder``
/// - ``WalletPassPayload``
/// - ``MockWalletPassProvider``
public protocol PaymentService: Sendable {
    func charge(amountMinorUnits: Int, currency: String, reference: String) async throws -> PaymentResult
}

/// The outcome of a charge: whether it succeeded and the order reference it applies to.
public struct PaymentResult: Sendable, Equatable {
    public let success: Bool
    public let reference: String
    public init(success: Bool, reference: String) {
        self.success = success; self.reference = reference
    }
}

/// Sandbox implementation so payment flows are buildable before you have a merchant ID.
public struct MockPaymentService: PaymentService {
    public init() {}
    public func charge(amountMinorUnits: Int, currency: String, reference: String) async throws -> PaymentResult {
        try await Task.sleep(for: .milliseconds(600))
        return PaymentResult(success: true, reference: reference)
    }
}
