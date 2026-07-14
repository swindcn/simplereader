import XCTest
@testable import PureVoice

final class InMemoryBookRepositoryTests: XCTestCase {
    func testSaveUpdateAndDeleteBook() async throws {
        let repository: any BookRepository = InMemoryBookRepository()
        var book = Book.fixture(title: "活着")

        try await repository.save(book)
        let savedBook = try await repository.book(id: book.id)
        XCTAssertEqual(savedBook?.title, "活着")

        book.position = ReadingPosition(href: "chapter-12.xhtml", progression: 0.35)
        try await repository.save(book)
        let updatedBook = try await repository.book(id: book.id)
        XCTAssertEqual(updatedBook?.position?.progression, 0.35)
        XCTAssertEqual(updatedBook?.title, "活着")
        XCTAssertEqual(updatedBook?.author, "余华")
        XCTAssertEqual(updatedBook?.canonicalFileURL, book.canonicalFileURL)

        try await repository.delete(id: book.id)
        let deletedBook = try await repository.book(id: book.id)
        XCTAssertNil(deletedBook)
    }

    func testAllBooksUsesStableNewestFirstOrder() async throws {
        let repository: any BookRepository = InMemoryBookRepository()
        let firstID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let newestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let sharedDate = Date(timeIntervalSince1970: 10)

        try await repository.save(.fixture(id: secondID, createdAt: sharedDate))
        try await repository.save(.fixture(id: newestID, createdAt: Date(timeIntervalSince1970: 20)))
        try await repository.save(.fixture(id: firstID, createdAt: sharedDate))

        let books = try await repository.allBooks()
        XCTAssertEqual(books.map(\.id), [newestID, firstID, secondID])
    }

    func testRecentBooksUsesLastOpenedDateWithCreatedDateFallbackAndLimit() async throws {
        let repository: any BookRepository = InMemoryBookRepository()
        let createdOnlyID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let recentlyOpenedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let oldestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        try await repository.save(.fixture(
            id: oldestID,
            lastOpenedAt: Date(timeIntervalSince1970: 5),
            createdAt: Date(timeIntervalSince1970: 1)
        ))
        try await repository.save(.fixture(
            id: recentlyOpenedID,
            lastOpenedAt: Date(timeIntervalSince1970: 30),
            createdAt: Date(timeIntervalSince1970: 2)
        ))
        try await repository.save(.fixture(
            id: createdOnlyID,
            createdAt: Date(timeIntervalSince1970: 20)
        ))

        let recent = try await repository.recentBooks(limit: 2)
        XCTAssertEqual(recent.map(\.id), [recentlyOpenedID, createdOnlyID])
        let empty = try await repository.recentBooks(limit: 0)
        XCTAssertTrue(empty.isEmpty)
        let negative = try await repository.recentBooks(limit: -1)
        XCTAssertTrue(negative.isEmpty)
    }

    func testReadingPositionClampsProgression() {
        XCTAssertEqual(ReadingPosition(href: "start.xhtml", progression: -0.25).progression, 0)
        XCTAssertEqual(ReadingPosition(href: "end.xhtml", progression: 1.25).progression, 1)
        XCTAssertEqual(ReadingPosition(href: "middle.xhtml", progression: 0.5).progression, 0.5)
        XCTAssertEqual(ReadingPosition(href: "invalid.xhtml", progression: .nan).progression, 0)
        XCTAssertEqual(ReadingPosition(href: "past-end.xhtml", progression: .infinity).progression, 1)
        XCTAssertEqual(ReadingPosition(href: "before-start.xhtml", progression: -.infinity).progression, 0)
    }
}
