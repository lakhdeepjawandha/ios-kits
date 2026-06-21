import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Drives an app-wide lock screen for finance-grade apps: locks when the app is backgrounded and
/// requires Face ID / Touch ID (passcode fallback) to return, with a configurable grace period.
///
/// Observe ``isLocked`` from SwiftUI to present a blocking lock overlay, and call ``unlock()`` from
/// the unlock button. By default the manager subscribes to the app lifecycle automatically; you can
/// instead disable that and forward `scenePhase` changes to the lifecycle hooks yourself.
///
/// ```swift
/// @State private var lock = AppLockManager(gracePeriod: 30)
///
/// var body: some View {
///     ContentView()
///         .overlay { if lock.isLocked { LockScreen { Task { await lock.unlock() } } } }
/// }
/// ```
///
/// Authentication is delegated to ``SecurityKit/authenticate(reason:)``, so biometric matching
/// happens inside the Secure Enclave and nothing leaves the device.
@MainActor
@Observable
public final class AppLockManager {

    /// Whether the app is currently locked and should present its lock UI.
    public private(set) var isLocked: Bool

    /// How long the app may stay backgrounded before it relocks on return. `0` relocks every time
    /// the app leaves the foreground; a larger value tolerates brief app switches.
    public var gracePeriod: TimeInterval

    /// User-facing reason shown in the authentication prompt during ``unlock()``.
    public var reason: String

    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private let authenticator: (String) async -> Bool
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    /// Create a lock manager.
    ///
    /// - Parameters:
    ///   - gracePeriod: Seconds the app may remain backgrounded before relocking. Default `0`.
    ///   - startsLocked: Whether the app begins locked (require unlock on launch). Default `true`.
    ///   - reason: Prompt message passed to authentication. Default `"Unlock to continue"`.
    ///   - observeLifecycle: When `true` (default) and `UIKit` is available, the manager subscribes
    ///     to background/foreground notifications automatically. Set `false` to drive locking
    ///     manually (e.g. via SwiftUI `scenePhase`).
    ///   - authenticator: Authentication closure. Defaults to ``SecurityKit/authenticate(reason:)``;
    ///     inject a stub in tests to avoid real biometrics.
    public init(gracePeriod: TimeInterval = 0,
                startsLocked: Bool = true,
                reason: String = "Unlock to continue",
                observeLifecycle: Bool = true,
                authenticator: @escaping (String) async -> Bool = { await SecurityKit.authenticate(reason: $0) }) {
        self.isLocked = startsLocked
        self.gracePeriod = gracePeriod
        self.reason = reason
        self.authenticator = authenticator
        if observeLifecycle { startObservingLifecycle() }
    }

    nonisolated deinit {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
    }

    /// Attempt to unlock by authenticating the user.
    ///
    /// - Returns: `true` if authentication succeeded and the app is now unlocked.
    @discardableResult
    public func unlock() async -> Bool {
        let success = await authenticator(reason)
        if success {
            isLocked = false
            backgroundedAt = nil
        }
        return success
    }

    /// Immediately lock the app (e.g. from a manual "Lock now" action).
    public func lock() {
        isLocked = true
    }

    // MARK: - Lifecycle hooks (also callable from SwiftUI `.scenePhase`)

    /// Record that the app entered the background. Call when the scene becomes inactive/background.
    ///
    /// - Parameter date: The moment the app backgrounded. Injectable for testing; defaults to now.
    public func applicationDidEnterBackground(at date: Date = Date()) {
        backgroundedAt = date
    }

    /// Re-evaluate the lock on return to the foreground, relocking if the grace period elapsed.
    ///
    /// - Parameter date: The moment the app foregrounded. Injectable for testing; defaults to now.
    public func applicationWillEnterForeground(at date: Date = Date()) {
        guard let backgroundedAt else { return }
        if date.timeIntervalSince(backgroundedAt) >= gracePeriod {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    // MARK: - Internals

    private func startObservingLifecycle() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationDidEnterBackground() }
            }
        )
        observers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationWillEnterForeground() }
            }
        )
        #endif
    }
}
