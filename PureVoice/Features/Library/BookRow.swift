import SwiftUI
import UIKit

struct BookRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let book: Book
    let accessibilityIdentifier: String
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: DesignTokens.stackGap) {
                cover
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
            .shadow(color: DesignTokens.onSurface.opacity(0.09), radius: 8, x: 0, y: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(for: book))
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .buttonStyle(.plain)
        .accessibilityHint("双击继续阅读。可使用辅助功能操作重命名或删除。")
        .accessibilityAction(named: Text("重命名"), onRename)
        .accessibilityAction(named: Text("删除"), onDelete)
        .contextMenu {
            Button(action: onRename) {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    static func accessibilityLabel(for book: Book) -> String {
        "\(book.title)，\(book.author)，已读百分之\(chinesePercentage(for: book))"
    }

    private var cover: some View {
        Group {
            if let coverURL = book.coverFileURL,
               let image = UIImage(contentsOfFile: coverURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    placeholderColor
                    Text(book.title.prefix(1))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 96, height: 132)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(book.title)
                .font(.headline)
                .foregroundStyle(DesignTokens.onSurface)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(book.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            progressSummary
            ProgressView(value: progress)
                .tint(DesignTokens.primary)
                .frame(height: 4)
        }
        .frame(minHeight: 132, alignment: .top)
    }

    @ViewBuilder
    private var progressSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                progressStatus
                progressPercentage
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack {
                progressStatus
                Spacer()
                progressPercentage
            }
        }
    }

    private var progressStatus: some View {
        Text(progress >= 1 ? "已完成" : "阅读中")
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.primary)
    }

    private var progressPercentage: some View {
        Text("\(percentage)%")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var progress: Double {
        book.position?.progression ?? 0
    }

    private var percentage: Int {
        Int((progress * 100).rounded())
    }

    private var placeholderColor: Color {
        let colors: [Color] = [
            Color(red: 0.08, green: 0.22, blue: 0.42),
            Color(red: 0.42, green: 0.12, blue: 0.18),
            Color(red: 0.08, green: 0.32, blue: 0.24),
            Color(red: 0.20, green: 0.20, blue: 0.24)
        ]
        let stableIndex = Int(book.id.uuid.0)
        return colors[stableIndex % colors.count]
    }

    private static func chinesePercentage(for book: Book) -> String {
        let value = Int(((book.position?.progression ?? 0) * 100).rounded())
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: value))?.replacingOccurrences(of: "〇", with: "零")
            ?? String(value)
    }
}
