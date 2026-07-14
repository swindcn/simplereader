import SwiftUI

struct ContinueReadingSection: View {
    let book: Book
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("继续阅读")
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.onSurface)
            BookRow(
                book: book,
                accessibilityIdentifier: "library.continue.book.\(book.id.uuidString)",
                onOpen: onOpen,
                onRename: onRename,
                onDelete: onDelete
            )
        }
    }
}
