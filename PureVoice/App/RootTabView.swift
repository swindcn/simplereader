import SwiftUI
@preconcurrency import ReadiumShared

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var readerBook: Book?
    @State private var hasRestoredLaunchState = false
    @State private var restorationNotice: UserFacingError?
    @State private var isPaywallPresented = false
    @State private var hasPresentedLaunchPaywall = false
    @StateObject private var preferencesStore: PreferencesStore
    @StateObject private var speechSession: SpeechSessionCoordinator
    @StateObject private var purchaseAccessStore: PurchaseAccessStore
    @StateObject private var purchaseManager: StoreKitPurchaseManager
    private let repository: any BookRepository
    private let importCoordinator: ImportCoordinator?
    private let webTransferViewModel: WebTransferViewModel?
    private let transferIdentityStore: (any TransferIdentityStoring)?
    private let serverGrantEntitlementProvider: (any ServerGrantEntitlementProviding)?
    private let libraryRefresh: LibraryRefreshSignal
    private let appStateRestorer: AppStateRestorer?

    init(
        repository: any BookRepository = InMemoryBookRepository(),
        importCoordinator: ImportCoordinator? = nil,
        webTransferViewModel: WebTransferViewModel? = nil,
        transferIdentityStore: (any TransferIdentityStoring)? = nil,
        serverGrantEntitlementProvider: (any ServerGrantEntitlementProviding)? = nil,
        libraryRefresh: LibraryRefreshSignal = LibraryRefreshSignal(),
        appStateRestorer: AppStateRestorer? = nil
    ) {
        self.repository = repository
        self.importCoordinator = importCoordinator
        self.webTransferViewModel = webTransferViewModel
        self.transferIdentityStore = transferIdentityStore
        self.serverGrantEntitlementProvider = serverGrantEntitlementProvider
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
        let purchaseAccessStore = PurchaseAccessStore()
        _purchaseAccessStore = StateObject(wrappedValue: purchaseAccessStore)
        _purchaseManager = StateObject(wrappedValue: StoreKitPurchaseManager(accessStore: purchaseAccessStore))
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
                appStateRestorer: appStateRestorer,
                requiresPurchase: purchaseAccessStore.requiresPurchase,
                onPurchaseRequired: { isPaywallPresented = true }
            )
        }
        .fullScreenCover(isPresented: $isPaywallPresented) {
            PaywallView(
                accessStore: purchaseAccessStore,
                purchaseManager: purchaseManager,
                onClose: { isPaywallPresented = false }
            )
            .appFontSize(preferencesStore.global.appFontSize)
            .appLanguage(appLanguage)
        }
        .fullScreenCover(isPresented: rootListeningPresented) {
            if let viewModel = speechSession.viewModel {
                ListeningView(viewModel: viewModel) {
                    Task {
                        _ = await viewModel.flushProgress()
                        speechSession.dismissListening(flushesProgress: false)
                    }
                } onEscapeToLibrary: {
                    _ = speechSession.endSession()
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
                    onOpen: { requestPaidAccess { speechSession.presentListening() } },
                    onTogglePlayback: { requestPaidAccess { viewModel.togglePlayback() } },
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
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
            await refreshServerGrantEntitlement()
            presentLaunchPaywallIfNeeded()
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

    private var isRootMiniPlayerVisible: Bool {
        guard let viewModel = speechSession.viewModel else { return false }
        return viewModel.isMiniPlayerVisible && !speechSession.isListeningPresented && readerBook == nil
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .library:
            LibraryView(
                repository: repository,
                libraryRefresh: libraryRefresh,
                webTransferViewModel: webTransferViewModel,
                reservesMiniPlayerSpace: isRootMiniPlayerVisible,
                onOpenBook: { book in requestPaidAccess { readerBook = book } },
                onMagicTapListen: { book in
                    requestPaidAccess {
                        Task { await speechSession.begin(book: book, presentsListening: true, startsPlayback: true) }
                    }
                }
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
                SettingsView(
                    store: preferencesStore,
                    subscriptionStatus: purchaseManager.subscriptionStatus,
                    onSubscriptionTapped: { isPaywallPresented = true }
                )
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

    private func requestPaidAccess(_ action: @escaping () -> Void) {
        guard purchaseAccessStore.requiresPurchase else {
            action()
            return
        }
        AccessibilityFeedback.notification(.warning)
        isPaywallPresented = true
    }

    private func presentLaunchPaywallIfNeeded() {
        guard !hasPresentedLaunchPaywall, purchaseAccessStore.requiresPurchase else { return }
        hasPresentedLaunchPaywall = true
        isPaywallPresented = true
    }

    private func refreshServerGrantEntitlement() async {
        guard let transferIdentityStore, let serverGrantEntitlementProvider else { return }
        do {
            let identity = try transferIdentityStore.identity()
            let entitlement = try await serverGrantEntitlementProvider.entitlement(for: identity)
            purchaseAccessStore.updateServerGrantEntitlement(entitlement)
        } catch {
            // Keep the cached entitlement when the server is temporarily unreachable.
        }
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
    @Environment(\.dismiss) private var dismiss
    @State private var listeningReturnLocator: Locator?
    let book: Book
    let repository: any BookRepository
    @ObservedObject var speechSession: SpeechSessionCoordinator
    @ObservedObject var preferencesStore: PreferencesStore
    let appStateRestorer: AppStateRestorer?
    let requiresPurchase: Bool
    let onPurchaseRequired: () -> Void

    var body: some View {
        ReaderView(
            book: book,
            repository: repository,
            preferencesStore: preferencesStore,
            appStateRestorer: appStateRestorer,
            onListen: { publication, locator in
                requestPaidAccess {
                    speechSession.begin(book: book, publication: publication, locator: locator)
                }
            },
            onMagicTap: { publication, locator in
                requestPaidAccess {
                    if isListeningCurrentBook, let viewModel = speechSession.viewModel {
                        viewModel.togglePlayback()
                    } else {
                        speechSession.begin(book: book, publication: publication, locator: locator, startsPlayback: true)
                    }
                }
            },
            onEscape: {
                if isListeningCurrentBook {
                    _ = speechSession.endSession()
                } else {
                    Task { await speechSession.flushProgress() }
                }
            },
            listeningReturnLocator: listeningReturnLocator,
            activeListeningLocator: isListeningCurrentBook ? speechSession.currentLocator : nil,
            isListeningActive: isListeningCurrentBook && speechSession.viewModel != nil
        )
        .appFontSize(preferencesStore.global.appFontSize)
        .appLanguage(appLanguage)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let viewModel = speechSession.viewModel,
               !speechSession.isListeningPresented {
                MiniPlayerView(
                    viewModel: viewModel,
                    onOpen: { requestPaidAccess { speechSession.presentListening() } },
                    onTogglePlayback: { requestPaidAccess { viewModel.togglePlayback() } },
                    onClose: {
                        let shouldReturnToReader = isListeningCurrentBook
                        let returnLocator = speechSession.endSession()
                        if shouldReturnToReader {
                            listeningReturnLocator = returnLocator
                        }
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
                        if isListeningCurrentBook {
                            listeningReturnLocator = returnLocator
                        }
                        speechSession.dismissListening(flushesProgress: false)
                    }
                } onEscapeToLibrary: {
                    _ = speechSession.endSession()
                    dismiss()
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

    private var isListeningCurrentBook: Bool {
        speechSession.currentBookID == book.id
    }

    private var sessionErrorPresented: Binding<Bool> {
        Binding(
            get: { speechSession.errorMessage != nil },
            set: { if !$0 { speechSession.dismissError() } }
        )
    }

    private func requestPaidAccess(_ action: @escaping () -> Void) {
        guard requiresPurchase else {
            action()
            return
        }
        AccessibilityFeedback.notification(.warning)
        onPurchaseRequired()
    }
}
