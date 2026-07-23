import SwiftUI

struct ReaderToolbar: View {
    @Environment(\.appStrings) private var strings
    let onListen: () -> Void
    let onSettings: () -> Void
    var backgroundColor: Color = Color(uiColor: .pureVoiceLightChrome)

    var body: some View {
        HStack(spacing: 12) {
            iconButton("headphones", label: strings.listen, identifier: "reader.listen", action: onListen)
            Spacer(minLength: 0)
            iconButton("textformat.size", label: strings.readerSettings, identifier: "reader.settings", action: onSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct ReaderHeaderToolbar: View {
    @Environment(\.appStrings) private var strings
    let onBack: () -> Void
    let onTableOfContents: () -> Void
    var backgroundColor: Color = Color(uiColor: .pureVoiceLightChrome)

    var body: some View {
        HStack {
            button("chevron.backward", label: strings.backToLibrary, identifier: "reader.back", action: onBack)
            Spacer()
            button("list.bullet", label: strings.tableOfContents, identifier: "reader.tableOfContents", action: onTableOfContents)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(backgroundColor)
    }

    private func button(
        _ systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
