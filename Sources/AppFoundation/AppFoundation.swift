import OSLog
import StoreKit
import SwiftUI

/// Cross-cutting app utilities: logging, review prompts, onboarding state.
public enum AppFoundation {
    public static let version = "0.1.0"
}

public extension Logger {
    /// Shared subsystem logger. Use `Logger.app("Network")` per feature.
    static func app(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: category)
    }
}

/// Requests an App Store review at a sensible moment (call after a positive event).
@MainActor
public enum ReviewPrompter {
    public static func requestIfAppropriate() {
#if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        AppStore.requestReview(in: scene)
#endif
    }
}

/// Simple onboarding completion flag backed by AppStorage.
public struct OnboardingState {
    @AppStorage("onboarding.completed") public var completed: Bool = false
    public init() {}
}
