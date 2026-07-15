import SwiftUI

struct RootTabView: View {
    @State private var readerBook: Book?
    private let repository: any BookRepository

    init(repository: any BookRepository = InMemoryBookRepository()) {
        self.repository = repository
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
            ReaderView(book: book, repository: repository)
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
}
