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
    private let webTransferViewModel: WebTransferViewModel?
    private let libraryRefresh: LibraryRefreshSignal
    private let appStateRestorer: AppStateRestorer?

    init(
        repository: any BookRepository = InMemoryBookRepository(),
        importCoordinator: ImportCoordinator? = nil,
        webTransferViewModel: WebTransferViewModel? = nil,
        libraryRefresh: LibraryRefreshSignal = LibraryRefreshSignal(),
        appStateRestorer: AppStateRestorer? = nil
    ) {
        self.repository = repository
        self.importCoordinator = importCoordinator
        self.webTransferViewModel = webTransferViewModel
        self.libraryRefresh = libraryRefresh
        self.appStateRestorer = appStateRestorer
        let preferencesStore = PreferencesStore(defaults: Self.preferencesDefaults())
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _speechSession = StateObject(wrappedValue: SpeechSessionCoordinator(
            repository: repository,
            preferencesStore: preferencesStore,
            appStateRestorer: appStateRestorer,
            onProgressSaved: {
                libraryRefresh.refresh()
            }
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
                        Label(tab.title(in: appStrings), systemImage: tab.systemImage)
                    }
            }
        }
        .appLanguage(appLanguage)
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
                .appFontSize(preferencesStore.global.appFontSize)
                .appLanguage(appLanguage)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel = speechSession.viewModel,
               !speechSession.isListeningPresented,
               readerBook == nil {
                MiniPlayerView(
                    viewModel: viewModel,
                    onOpen: speechSession.presentListening,
                    onClose: { _ = speechSession.endSession() },
                    reservesTabBarSpace: true
                )
                .appFontSize(preferencesStore.global.appFontSize)
                .appLanguage(appLanguage)
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            Task { await speechSession.flushProgress() }
        }
        .alert(appStrings.listeningNotice, isPresented: rootSessionErrorPresented) {
            if speechSession.hasPendingProgressRetry {
                Button(appStrings.retrySave) { speechSession.retryPendingProgress() }
            }
            Button(appStrings.ok, role: .cancel) { speechSession.dismissError() }
        } message: {
            Text(speechSession.errorMessage ?? appStrings.unknownError)
        }
        .alert(appStrings.restoreNotice, isPresented: restorationNoticePresented) {
            Button(appStrings.ok, role: .cancel) { restorationNotice = nil }
        } message: {
            Text(restorationNoticeMessage)
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

    private var appLanguage: EffectiveAppLanguage {
        preferencesStore.global.appLanguage.effectiveLanguage
    }

    private var appStrings: AppStrings {
        AppStrings(language: appLanguage)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .library:
            LibraryView(
                repository: repository,
                libraryRefresh: libraryRefresh,
                webTransferViewModel: webTransferViewModel,
                onOpenBook: { readerBook = $0 }
            )
            .appFontSize(preferencesStore.global.appFontSize)
            .appLanguage(appLanguage)
        case .importBooks:
            if let importCoordinator, let webTransferViewModel {
                ImportView(
                    coordinator: importCoordinator,
                    webTransferViewModel: webTransferViewModel
                )
                    .appFontSize(preferencesStore.global.appFontSize)
                    .appLanguage(appLanguage)
            } else {
                Text(appStrings.importUnavailable)
                    .appFontSize(preferencesStore.global.appFontSize)
                    .appLanguage(appLanguage)
            }
        case .settings:
            NavigationView {
                SettingsView(store: preferencesStore)
                    .appFontSize(preferencesStore.global.appFontSize)
                    .appLanguage(appLanguage)
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

    private var restorationNoticeMessage: String {
        guard let restorationNotice else { return appStrings.restoredReadableState }
        return "\(restorationNotice.message)\n\(restorationNotice.recoveryAction)"
    }

    private func restoreLaunchStateIfNeeded() async {
        guard !hasRestoredLaunchState else { return }
        hasRestoredLaunchState = true
        guard let plan = appStateRestorer?.restoreLaunchState() else { return }

        switch plan {
        case let .markImportFailed(bookID, originalFileURL, error):
            importCoordinator?.restoreInterruptedImport(bookID: bookID, originalFileURL: originalFileURL)
            restorationNotice = error
            libraryRefresh.refresh()
        case let .reopenReader(bookID, _):
            readerBook = try? await repository.book(id: bookID)
        case let .reopenListening(bookID, position, _):
            guard let book = try? await repository.book(id: bookID) else { return }
            await speechSession.restorePausedSession(
                book: book,
                position: position,
                presentsListening: true
            )
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
            listeningReturnLocator: listeningReturnLocator,
            activeListeningLocator: speechSession.viewModel == nil ? nil : speechSession.currentLocator
        )
        .appFontSize(preferencesStore.global.appFontSize)
        .appLanguage(appLanguage)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel = speechSession.viewModel,
               !speechSession.isListeningPresented {
                MiniPlayerView(
                    viewModel: viewModel,
                    onOpen: speechSession.presentListening,
                    onClose: {
                        listeningReturnLocator = speechSession.endSession()
                    }
                )
                .appFontSize(preferencesStore.global.appFontSize)
                .appLanguage(appLanguage)
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
                .appFontSize(preferencesStore.global.appFontSize)
                .appLanguage(appLanguage)
            }
        }
        .alert(appStrings.listeningNotice, isPresented: sessionErrorPresented) {
            if speechSession.hasPendingProgressRetry {
                Button(appStrings.retrySave) { speechSession.retryPendingProgress() }
            }
            Button(appStrings.ok, role: .cancel) { speechSession.dismissError() }
        } message: {
            Text(speechSession.errorMessage ?? appStrings.unknownError)
        }
    }

    private var appLanguage: EffectiveAppLanguage {
        preferencesStore.global.appLanguage.effectiveLanguage
    }

    private var appStrings: AppStrings {
        AppStrings(language: appLanguage)
    }

    private var sessionErrorPresented: Binding<Bool> {
        Binding(
            get: { speechSession.errorMessage != nil },
            set: { if !$0 { speechSession.dismissError() } }
        )
    }
}
