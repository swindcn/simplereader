import SwiftUI

struct RootTabView: View {
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
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .library:
            LibraryView(repository: repository)
        case .importBooks, .settings:
            Text(tab.title)
        }
    }
}
