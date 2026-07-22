import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @ObservedObject private var libraryRefresh: LibraryRefreshSignal
    @State private var renameTarget: Book?
    @State private var renameTitle = ""
    @State private var deleteTarget: Book?

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
            Group {
                if viewModel.isLoading && viewModel.continueReadingBook == nil && viewModel.recentBooks.isEmpty {
                    ProgressView("正在载入书架")
                } else if viewModel.continueReadingBook == nil && viewModel.recentBooks.isEmpty {
                    emptyState
                } else {
                    libraryContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("简声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    brandTitle
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.refreshAndReceiveWebTransfers() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("刷新书架并接收网站传书")
                }
            }
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
        .confirmationDialog("删除这本书？", isPresented: deletePresented, presenting: deleteTarget) { book in
            Button("删除《\(book.title)》", role: .destructive) {
                Task { await viewModel.delete(book) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("此操作无法撤销。")
        }
        .alert("操作失败", isPresented: errorPresented) {
            Button("好", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "发生未知错误")
        }
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let book = viewModel.continueReadingBook {
                    ContinueReadingSection(
                        book: book,
                        onOpen: { Task { await viewModel.open(book) } },
                        onRename: { beginRename(book) },
                        onDelete: { deleteTarget = book }
                    )
                }

                if !viewModel.recentBooks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("最近阅读")
                            .font(.title2.bold())
                            .foregroundStyle(DesignTokens.onSurface)
                        ForEach(viewModel.recentBooks) { book in
                            BookRow(
                                book: book,
                                accessibilityIdentifier: "library.recent.book.\(book.id.uuidString)",
                                onOpen: { Task { await viewModel.open(book) } },
                                onRename: { beginRename(book) },
                                onDelete: { deleteTarget = book }
                            )
                        }
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

    private var brandTitle: some View {
        HStack(spacing: 12) {
            ZStack {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
                Text("简声标志")
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("library.brandLogo")
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("简声")
                    .font(.title2.bold())
                    .foregroundStyle(DesignTokens.onSurface)
            }
        }
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

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
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
