import SwiftUI

struct ReaderToolbar: View {
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void
    let onListen: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iconButton("chevron.left", label: "上一页", identifier: "reader.previousPage", action: onPreviousPage)
            Spacer(minLength: 0)
            iconButton("chevron.right", label: "下一页", identifier: "reader.nextPage", action: onNextPage)
            Spacer(minLength: 0)
            iconButton("headphones", label: "听书", identifier: "reader.listen", action: onListen)
            Spacer(minLength: 0)
            iconButton("textformat.size", label: "设置", identifier: "reader.settings", action: onSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
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
    let onBack: () -> Void
    let onTableOfContents: () -> Void

    var body: some View {
        HStack {
            button("chevron.backward", label: "返回书架", identifier: "reader.back", action: onBack)
            Spacer()
            button("list.bullet", label: "目录", identifier: "reader.tableOfContents", action: onTableOfContents)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.regularMaterial)
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
