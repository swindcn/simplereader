import SwiftUI
@preconcurrency import ReadiumShared

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var readerBook: Book?
    @State private var hasRestoredLaunchState = false
    @State private var restorationNotice: UserFacingError?
    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var speechSession: SpeechSessionCoordinator
    private let repository: any BookRepository
    private let importCoordinator: ImportCoordinator?
    private let libraryRefresh: LibraryRefreshSignal
    private let appStateRestorer: AppStateRestorer?

    init(
        repository: any BookRepository = InMemoryBookRepository(),
        importCoordinator: ImportCoordinator? = nil,
        libraryRefresh: LibraryRefreshSignal = LibraryRefreshSignal(),
        appStateRestorer: AppStateRestorer? = nil
    ) {
        self.repository = repository
        self.importCoordinator = importCoordinator
        self.libraryRefresh = libraryRefresh
        self.appStateRestorer = appStateRestorer
        let preferencesStore = PreferencesStore(defaults: Self.preferencesDefaults())
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _speechSession = StateObject(wrappedValue: SpeechSessionCoordinator(
            repository: repository,
            preferencesStore: preferencesStore,
            appStateRestorer: appStateRestorer
        ))
    }

    private static func preferencesDefaults() -> UserDefaults {
#if DEBUG
        if let suite = ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_SETTINGS_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_SETTINGS_RESET"] == "1" {
                defaults.removePersistentDomain(forName: suite)
            }
            return defaults
        }
#endif
        return .standard
    }

    var body: some View {
        TabView {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
            }
        }
        .fullScreenCover(item: $readerBook) { book in
            ReaderListeningHost(
                book: book,
                repository: repository,
                speechSession: speechSession,
                preferencesStore: preferencesStore,
                appStateRestorer: appStateRestorer
            )
        }
        .fullScreenCover(isPresented: rootListeningPresented) {
            if let viewModel = speechSession.viewModel {
                ListeningView(viewModel: viewModel) {
                    Task {
                        _ = await viewModel.flushProgress()
                        speechSession.dismissListening(flushesProgress: false)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel = speechSession.viewModel,
               !speechSession.isListeningPresented,
               readerBook == nil {
                MiniPlayerView(viewModel: viewModel, onOpen: speechSession.presentListening)
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            Task { await speechSession.flushProgress() }
        }
        .alert("听书提示", isPresented: rootSessionErrorPresented) {
            if speechSession.hasPendingProgressRetry {
                Button("重试保存") { speechSession.retryPendingProgress() }
            }
            Button("好", role: .cancel) { speechSession.dismissError() }
        } message: {
            Text(speechSession.errorMessage ?? "发生未知错误")
        }
        .alert("恢复提示", isPresented: restorationNoticePresented) {
            Button("好", role: .cancel) { restorationNotice = nil }
        } message: {
            Text(restorationNotice?.message ?? "已恢复到可继续阅读的状态。")
        }
        .task {
            await restoreLaunchStateIfNeeded()
        }
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_READER_EPUB"] != nil,
                  readerBook == nil
            else { return }
            readerBook = (try? await repository.allBooks())?.first
        }
#endif
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .library:
            LibraryView(
                repository: repository,
                libraryRefresh: libraryRefresh,
                onOpenBook: { readerBook = $0 }
            )
        case .importBooks:
            if let importCoordinator {
                ImportView(coordinator: importCoordinator)
            } else {
                Text("导入功能暂不可用")
            }
        case .settings:
            NavigationView {
                SettingsView(store: preferencesStore)
            }
            .navigationViewStyle(.stack)
        }
    }

    private var rootListeningPresented: Binding<Bool> {
        Binding(
            get: { readerBook == nil && speechSession.isListeningPresented },
            set: { if !$0 { speechSession.dismissListening() } }
        )
    }

    private var rootSessionErrorPresented: Binding<Bool> {
        Binding(
            get: { readerBook == nil && speechSession.errorMessage != nil },
            set: { if !$0 { speechSession.dismissError() } }
        )
    }

    private var restorationNoticePresented: Binding<Bool> {
        Binding(
            get: { restorationNotice != nil },
            set: { if !$0 { restorationNotice = nil } }
        )
    }

    private func restoreLaunchStateIfNeeded() async {
        guard !hasRestoredLaunchState else { return }
        hasRestoredLaunchState = true
        guard let plan = appStateRestorer?.restoreLaunchState() else { return }

        switch plan {
        case let .markImportFailed(_, _, error):
            restorationNotice = error
            libraryRefresh.refresh()
        case let .reopenReader(bookID, _), let .reopenListening(bookID, _, _):
            readerBook = try? await repository.book(id: bookID)
        }
    }
}

private struct ReaderListeningHost: View {
    @State private var listeningReturnLocator: Locator?
    let book: Book
    let repository: any BookRepository
    @ObservedObject var speechSession: SpeechSessionCoordinator
    @ObservedObject var preferencesStore: PreferencesStore
    let appStateRestorer: AppStateRestorer?

    var body: some View {
        ReaderView(
            book: book,
            repository: repository,
            preferencesStore: preferencesStore,
            appStateRestorer: appStateRestorer,
            onListen: { publication, locator in
                speechSession.begin(book: book, publication: publication, locator: locator)
            },
            listeningReturnLocator: listeningReturnLocator
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel = speechSession.viewModel,
               !speechSession.isListeningPresented {
                MiniPlayerView(viewModel: viewModel, onOpen: speechSession.presentListening)
            }
        }
        .fullScreenCover(isPresented: $speechSession.isListeningPresented) {
            if let viewModel = speechSession.viewModel {
                ListeningView(viewModel: viewModel) {
                    Task {
                        let returnLocator = viewModel.currentLocator
                        _ = await viewModel.flushProgress()
                        listeningReturnLocator = returnLocator
                        speechSession.dismissListening(flushesProgress: false)
                    }
                }
            }
        }
        .alert("听书提示", isPresented: sessionErrorPresented) {
            if speechSession.hasPendingProgressRetry {
                Button("重试保存") { speechSession.retryPendingProgress() }
            }
            Button("好", role: .cancel) { speechSession.dismissError() }
        } message: {
            Text(speechSession.errorMessage ?? "发生未知错误")
        }
    }

    private var sessionErrorPresented: Binding<Bool> {
        Binding(
            get: { speechSession.errorMessage != nil },
            set: { if !$0 { speechSession.dismissError() } }
        )
    }
}
