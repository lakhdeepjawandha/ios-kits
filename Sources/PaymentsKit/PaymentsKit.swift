import Foundation

/// Apple Pay, Tap to Pay on iPhone, and PassKit/Wallet passes.
/// NOTE: these require a paid Apple Developer account + entitlements to run on device.
/// Build the protocol + sandbox/mock implementation now; wire the real merchant flow later.
public protocol PaymentService: Sendable {
    func charge(amountMinorUnits: Int, currency: String, reference: String) async throws -> PaymentResult
}

public struct PaymentResult: Sendable {
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
