import SwiftUI
@preconcurrency import ReadiumShared

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var readerBook: Book?
    @StateObject private var speechSession: SpeechSessionCoordinator
    private let repository: any BookRepository

    init(repository: any BookRepository = InMemoryBookRepository()) {
        self.repository = repository
        _speechSession = StateObject(wrappedValue: SpeechSessionCoordinator(repository: repository))
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
                speechSession: speechSession
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
            LibraryView(repository: repository, onOpenBook: { readerBook = $0 })
        case .importBooks, .settings:
            Text(tab.title)
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
}

private struct ReaderListeningHost: View {
    @State private var listeningReturnLocator: Locator?
    let book: Book
    let repository: any BookRepository
    @ObservedObject var speechSession: SpeechSessionCoordinator

    var body: some View {
        ReaderView(
            book: book,
            repository: repository,
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
