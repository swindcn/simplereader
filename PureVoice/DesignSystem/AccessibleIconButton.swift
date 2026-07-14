import SwiftUI

struct AccessibleIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let hint: LocalizedStringKey?
    let action: () -> Void

    init(
        systemName: String,
        label: LocalizedStringKey,
        hint: LocalizedStringKey? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.label = label
        self.hint = hint
        self.action = action
    }

    var body: some View {
        if let hint {
            button
                .accessibilityHint(hint)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .semibold))
                .frame(
                    minWidth: DesignTokens.minimumTouchTarget,
                    minHeight: DesignTokens.minimumTouchTarget
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
