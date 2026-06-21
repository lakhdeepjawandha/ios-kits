import SwiftUI

// MARK: - Banner severity

/// Semantic severity level for a ``Banner``.
public enum BannerSeverity {
    /// Neutral informational message.
    case info
    /// Positive / success confirmation.
    case success
    /// Caution / degraded-state warning.
    case warning
    /// Error / failure message.
    case error

    var icon: String {
        switch self {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    func foreground(_ theme: Theme) -> Color {
        switch self {
        case .info:    return theme.accent
        case .success: return theme.positive
        case .warning: return theme.warning
        case .error:   return theme.negative
        }
    }
}

// MARK: - Banner / Toast

/// An inline banner or toast notification strip.
///
/// Display inline in a `VStack` for persistent banners, or overlay with `.overlay(alignment: .top)`
/// for toast-style notifications.
///
/// ```swift
/// Banner("Trade executed successfully", severity: .success, isDismissible: true)
/// ```
public struct Banner: View {
    @Environment(\.theme) private var theme
    @State private var dismissed = false

    private let message: String
    private let severity: BannerSeverity
    private let isDismissible: Bool
    private let action: (label: String, handler: () -> Void)?

    /// Creates a banner.
    /// - Parameters:
    ///   - message: The message body.
    ///   - severity: Visual severity level. Defaults to ``BannerSeverity/info``.
    ///   - isDismissible: Whether a dismiss (×) button is shown. Defaults to `false`.
    ///   - action: Optional inline action expressed as `(label, handler)`.
    public init(
        _ message: String,
        severity: BannerSeverity = .info,
        isDismissible: Bool = false,
        action: (label: String, handler: () -> Void)? = nil
    ) {
        self.message = message
        self.severity = severity
        self.isDismissible = isDismissible
        self.action = action
    }

    public var body: some View {
        if !dismissed {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: severity.icon)
                    .font(.system(size: DS.FontSize.subheadline, weight: .semibold))
                    .foregroundStyle(severity.foreground(theme))

                Text(message)
                    .dsCaption()
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let action {
                    Button(action.label, action: action.handler)
                        .dsCaption()
                        .fontWeight(.semibold)
                        .foregroundStyle(severity.foreground(theme))
                }

                if isDismissible {
                    Button {
                        withAnimation(.easeOut(duration: DS.Animation.fast)) {
                            dismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: DS.FontSize.caption, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm + DS.Spacing.xs)
            .background(
                severity.foreground(theme).opacity(0.12),
                in: RoundedRectangle(cornerRadius: DS.Radius.sm)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(severity.foreground(theme).opacity(0.3), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Banner / Toast") {
    let theme = ThemePreset.fintechNavy.theme
    return VStack(spacing: DS.Spacing.sm) {
        Banner("Market data is live.", severity: .info)
        Banner("Order filled at $189.30", severity: .success, isDismissible: true)
        Banner("High volatility detected.", severity: .warning, action: ("Details", {}))
        Banner("Connection lost. Retrying…", severity: .error, isDismissible: true)
    }
    .padding()
    .dsTheme(theme)
    .background(theme.background)
}
