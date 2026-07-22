import SwiftUI
import UIKit

struct LibraryView: View {
    @Environment(\.appFontSize) private var appFontSize
    @StateObject private var viewModel: LibraryViewModel
    @ObservedObject private var libraryRefresh: LibraryRefreshSignal
    @State private var renameTarget: Book?
    @State private var renameTitle = ""
    @State private var deleteTarget: Book?
    @State private var actionTarget: Book?
    private let shelfColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    init(
        repository: any BookRepository,
        libraryRefresh: LibraryRefreshSignal = LibraryRefreshSignal(),
        webTransferViewModel: WebTransferViewModel? = nil,
        onOpenBook: @escaping (Book) -> Void = { _ in }
    ) {
        self.libraryRefresh = libraryRefresh
        _viewModel = StateObject(
            wrappedValue: LibraryViewModel(
                repository: repository,
                receiveWebTransfers: webTransferViewModel.map { viewModel in
                    {
                        _ = await viewModel.receivePendingItems()
                        return viewModel.error
                    }
                },
                onOpenBook: onOpenBook
            )
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                libraryHeader
                Divider()
                    .accessibilityHidden(true)
                Group {
                    if viewModel.isLoading && viewModel.continueReadingBook == nil && viewModel.shelfBooks.isEmpty {
                        ProgressView("正在载入书架")
                    } else if viewModel.continueReadingBook == nil && viewModel.shelfBooks.isEmpty {
                        emptyState
                    } else {
                        libraryContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .task { await viewModel.load() }
        .onChange(of: libraryRefresh.generation) { _ in
            Task { await viewModel.load() }
        }
        .alert("重命名", isPresented: renamePresented, presenting: renameTarget) { book in
            TextField("书名", text: $renameTitle)
            Button("取消", role: .cancel) {}
            Button("保存") {
                Task { await viewModel.rename(book, to: renameTitle) }
            }
        } message: { book in
            Text("为《\(book.title)》输入新书名")
        }
        .sheet(item: $actionTarget) { book in
            BookActionsSheet(
                book: book,
                onRename: {
                    actionTarget = nil
                    beginRename(book)
                },
                onDelete: {
                    actionTarget = nil
                    deleteTarget = book
                },
                onCancel: { actionTarget = nil }
            )
            .appFontSize(appFontSize)
        }
        .sheet(item: $deleteTarget) { book in
            DeleteBookSheet(
                book: book,
                onCancel: { deleteTarget = nil },
                onDelete: {
                    deleteTarget = nil
                    Task { await viewModel.delete(book) }
                }
            )
            .appFontSize(appFontSize)
        }
        .alert("操作失败", isPresented: errorPresented) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "发生未知错误")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let book = viewModel.continueReadingBook {
                    ContinueReadingSection(
                        book: book,
                        onOpen: { Task { await viewModel.open(book) } },
                        onRename: { beginRename(book) },
                        onDelete: { actionTarget = book }
                    )
                }

                if !viewModel.shelfBooks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("我的书籍")
                            .font(.title2.bold())
                            .foregroundStyle(DesignTokens.onSurface)
                        LazyVGrid(columns: shelfColumns, alignment: .leading, spacing: 18) {
                            ForEach(viewModel.shelfBooks) { book in
                                BookGridItem(
                                    book: book,
                                    accessibilityIdentifier: "library.shelf.book.\(book.id.uuidString)",
                                    onOpen: { Task { await viewModel.open(book) } },
                                    onRename: { beginRename(book) },
                                    onDelete: { actionTarget = book }
                                )
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                } else if viewModel.continueReadingBook != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("我的书籍")
                            .font(.title2.bold())
                            .foregroundStyle(DesignTokens.onSurface)
                        Text("当前只有一本书，已放在继续阅读中。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.edgeMargin)
            .padding(.vertical, DesignTokens.stackGap)
        }
        .refreshable { await viewModel.refreshAndReceiveWebTransfers() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)
                .frame(height: DesignTokens.minimumTouchTarget + DesignTokens.stackGap)
                .accessibilityHidden(true)
        }
    }

    private var libraryHeader: some View {
        HStack {
            brandTitle
            Spacer(minLength: 12)
            Button {
                Task { await viewModel.refreshAndReceiveWebTransfers() }
            } label: {
                Image("RefreshAction")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(DesignTokens.onSurface)
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("刷新书架并接收网站传书")
        }
        .padding(.horizontal, DesignTokens.edgeMargin)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.header")
    }

    private struct BookGridItem: View {
        let book: Book
        let accessibilityIdentifier: String
        let onOpen: () -> Void
        let onRename: () -> Void
        let onDelete: () -> Void
        @ScaledMetric(relativeTo: .headline) private var titleReserveHeight: CGFloat = 46

        var body: some View {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 7) {
                    cover
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(DesignTokens.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: titleReserveHeight, alignment: .topLeading)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(percentage)%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    ProgressView(value: progress)
                        .tint(DesignTokens.primary)
                        .frame(height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BookRow.accessibilityLabel(for: book))
                .accessibilityIdentifier(accessibilityIdentifier)
            }
            .buttonStyle(.plain)
            .accessibilityHint("双击继续阅读。可使用辅助功能操作重命名或删除。")
            .accessibilityAction(named: Text("重命名"), onRename)
            .accessibilityAction(named: Text("删除"), onDelete)
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in onDelete() })
        }

        private var cover: some View {
            GeometryReader { proxy in
                Group {
                    if let coverURL = book.coverFileURL,
                       let image = UIImage(contentsOfFile: coverURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            placeholderColor
                            Text(book.title.prefix(1))
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            }
            .aspectRatio(0.72, contentMode: .fit)
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
    }

    private var brandTitle: some View {
        HStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
                .accessibilityIdentifier("library.brandLogo")
            Text("简声")
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.onSurface)
        }
        .frame(width: 128, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("简声")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.primary)
                .accessibilityHidden(true)
            Text("书架还是空的")
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.onSurface)
            Text("从“导入”添加本地书籍")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                Task { await viewModel.refreshAndReceiveWebTransfers() }
            } label: {
                Label("刷新接收网站传书", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
            .accessibilityHint("检查网页上传的书籍并导入到书架")
        }
        .multilineTextAlignment(.center)
        .padding(DesignTokens.edgeMargin)
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private func beginRename(_ book: Book) {
        renameTitle = book.title
        renameTarget = book
    }
}

private struct BookActionsSheet: View {
    let book: Book
    let onRename: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.onSurface)
                    .lineLimit(2)
                Text(book.author)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(spacing: 12) {
                Button(action: onRename) {
                    Label("重命名", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.action.rename")

                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("library.action.delete")

                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityIdentifier("library.action.cancel")
            }
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

private struct DeleteBookSheet: View {
    let book: Book
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("删除这本书？")
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.onSurface)
                Text("《\(book.title)》将从书架移除，此操作无法撤销。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityIdentifier("library.delete.cancel")
                Button("删除", role: .destructive, action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityIdentifier("library.delete.confirm")
            }
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}
