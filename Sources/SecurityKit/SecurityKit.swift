import Foundation
import LocalAuthentication

/// Biometric gate for finance-grade apps.
///
/// `SecurityKit` is a thin, dependency-free wrapper around `LocalAuthentication`. Pair it with
/// ``Keychain`` for secret storage and ``AppLockManager`` for a foreground lock screen.
///
/// ## Secure Enclave & what stays on device
/// Face ID / Touch ID matching is performed entirely inside the device's **Secure Enclave** — a
/// dedicated coprocessor isolated from the main CPU and OS. Raw biometric data never leaves the
/// chip and is **never** exposed to your app: you only ever receive a success/failure result.
/// Nothing in this module transmits any data off the device.
///
/// - Important: Add an `NSFaceIDUsageDescription` key to your app's `Info.plist`, or Face ID
///   evaluation will fail at runtime.
public enum SecurityKit {

    /// Prompt the user for Face ID / Touch ID, falling back to the device passcode.
    ///
    /// Uses `LAPolicy.deviceOwnerAuthentication`, so if biometrics are unavailable or repeatedly
    /// fail, the system automatically offers the device passcode. A fresh `LAContext` is created
    /// per call so prior evaluations cannot be silently reused.
    ///
    /// The biometric comparison happens inside the Secure Enclave; your app only observes the
    /// boolean outcome.
    ///
    /// - Parameter reason: User-facing explanation shown in the system prompt (e.g. "Unlock your
    ///   account"). Must be non-empty.
    /// - Returns: `true` if the user authenticated successfully, `false` otherwise (cancellation,
    ///   failure, or no enrolled authentication method).
    public static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { cont in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    /// Whether the device can currently authenticate the owner via biometrics **or** passcode.
    ///
    /// Useful as an availability guard before presenting a lock UI, and for skipping
    /// biometric-dependent tests on machines/CI without an enrolled authentication method.
    ///
    /// - Returns: `true` if `LAPolicy.deviceOwnerAuthentication` can be evaluated right now.
    public static func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// The kind of biometry available on this device (`.faceID`, `.touchID`, `.opticID`, or
    /// `.none`).
    ///
    /// Querying `biometryType` requires a prior `canEvaluatePolicy` call on the context, which this
    /// accessor performs internally. Use it to tailor copy and iconography (e.g. "Use Face ID").
    public static var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
}
