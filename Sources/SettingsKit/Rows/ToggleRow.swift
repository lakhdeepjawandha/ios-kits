import SwiftUI

/// A settings row presenting a labelled on/off `Toggle` bound to a `Bool`.
///
/// ```swift
/// ToggleRow("Enable notifications", systemImage: "bell", isOn: $notificationsEnabled)
/// ```
public struct ToggleRow: View {
    private let title: String
    private let systemImage: String?
    @Binding private var isOn: Bool

    /// Creates a toggle row.
    /// - Parameters:
    ///   - title: The row's label.
    ///   - systemImage: Optional SF Symbol shown before the label.
    ///   - isOn: Binding to the toggle's state.
    public init(_ title: String, systemImage: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            settingsRowLabel(title, systemImage: systemImage)
        }
    }
}

#Preview("Toggle Row") {
    @Previewable @State var isOn = true
    return Form {
        ToggleRow("Enable notifications", systemImage: "bell", isOn: $isOn)
        ToggleRow("Plain toggle", isOn: $isOn)
    }
}
