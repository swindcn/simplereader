import SwiftUI

@main
struct PureVoiceApp: App {
    private let repository: any BookRepository

    init() {
        LibraryNavigationBarStyle.apply()
        repository = Self.makeRepository()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(repository: repository)
        }
    }

    private static func makeRepository() -> any BookRepository {
#if DEBUG
        if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_LIBRARY_SEED"] == "1" {
            return InMemoryBookRepository(books: uiTestBooks)
        }
#endif
        return InMemoryBookRepository()
    }

#if DEBUG
    private static let uiTestBooks: [Book] = [
        seededBook("11111111-1111-1111-1111-111111111111", "活着", "余华", 0.35, 400),
        seededBook("22222222-2222-2222-2222-222222222222", "许三观卖血记", "余华", 0.62, 300),
        seededBook("33333333-3333-3333-3333-333333333333", "围城", "钱钟书", 0.12, 200),
        seededBook("44444444-4444-4444-4444-444444444444", "平凡的世界", "路遥", 1, 100)
    ]

    private static func seededBook(
        _ id: String,
        _ title: String,
        _ author: String,
        _ progression: Double,
        _ openedAt: TimeInterval
    ) -> Book {
        let id = UUID(uuidString: id)!
        return Book(
            id: id,
            title: title,
            author: author,
            format: .epub,
            originalFileURL: URL(fileURLWithPath: "/tmp/\(id)/original.epub"),
            canonicalFileURL: URL(fileURLWithPath: "/tmp/\(id)/publication.epub"),
            coverFileURL: nil,
            position: ReadingPosition(href: "chapter.xhtml", progression: progression),
            lastOpenedAt: Date(timeIntervalSince1970: openedAt),
            createdAt: Date(timeIntervalSince1970: openedAt)
        )
    }
#endif
}
