#if canImport(UIKit)
import UIKit

/// Conveniences for UIKit haptic feedback. All methods are safe to call from any thread
/// but dispatch to the main thread internally.
@MainActor
public enum Haptics {
    /// Light tap for successful actions (save, purchase, check-in).
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Medium tap for cautionary states (low balance, expiry warning).
    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Heavy tap for destructive or failed actions.
    public static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Subtle click for selection changes (picker rows, toggles).
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Physical impact feedback at the given intensity.
    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
#endif
