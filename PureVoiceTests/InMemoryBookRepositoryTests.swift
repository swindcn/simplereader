import XCTest
@testable import PureVoice

final class InMemoryBookRepositoryTests: XCTestCase {
    func testSaveUpdateAndDeleteBook() async throws {
        let repository: any BookRepository = InMemoryBookRepository()
        let originalFileURL = URL(fileURLWithPath: "/tmp/custom/original.mobi")
        let canonicalFileURL = URL(fileURLWithPath: "/tmp/custom/publication.epub")
        let coverFileURL = URL(fileURLWithPath: "/tmp/custom/cover.jpg")
        var book = Book.fixture(
            title: "兄弟",
            author: "测试作者",
            format: .mobi,
            originalFileURL: originalFileURL,
            canonicalFileURL: canonicalFileURL,
            coverFileURL: coverFileURL,
            position: ReadingPosition(href: "chapter-1.xhtml", progression: 0.1),
            lastOpenedAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 100)
        )

        try await repository.save(book)
        let savedBook = try await repository.book(id: book.id)
        XCTAssertEqual(savedBook, book)

        book.position = ReadingPosition(href: "chapter-12.xhtml", progression: 0.35)
        try await repository.save(book)
        let updatedBook = try await repository.book(id: book.id)
        XCTAssertEqual(updatedBook, book)

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

    func testAllBooksTreatsNonFiniteDatesAsOldestWithStableTieBreaking() async throws {
        let repository: any BookRepository = InMemoryBookRepository()
        let nanID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let positiveInfinityID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let negativeInfinityID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let finiteID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

        try await repository.save(.fixture(
            id: nanID,
            createdAt: Date(timeIntervalSinceReferenceDate: .nan)
        ))
        try await repository.save(.fixture(
            id: positiveInfinityID,
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)
        ))
        try await repository.save(.fixture(
            id: negativeInfinityID,
            createdAt: Date(timeIntervalSinceReferenceDate: -.infinity)
        ))
        try await repository.save(.fixture(
            id: finiteID,
            createdAt: Date(timeIntervalSinceReferenceDate: 10)
        ))

        let expectedIDs = [finiteID, nanID, positiveInfinityID, negativeInfinityID]
        let firstQuery = try await repository.allBooks().map(\.id)
        let secondQuery = try await repository.allBooks().map(\.id)
        XCTAssertEqual(firstQuery, expectedIDs)
        XCTAssertEqual(secondQuery, expectedIDs)
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

    func testRecentBooksUsesStableTieBreakerForEqualEffectiveDates() async throws {
        let repository: any BookRepository = InMemoryBookRepository()
        let firstID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let secondID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let sharedDate = Date(timeIntervalSinceReferenceDate: 10)

        try await repository.save(.fixture(
            id: secondID,
            lastOpenedAt: sharedDate,
            createdAt: sharedDate
        ))
        try await repository.save(.fixture(
            id: firstID,
            lastOpenedAt: sharedDate,
            createdAt: sharedDate
        ))

        let firstQuery = try await repository.recentBooks(limit: 2).map(\.id)
        let secondQuery = try await repository.recentBooks(limit: 2).map(\.id)
        XCTAssertEqual(firstQuery, [firstID, secondID])
        XCTAssertEqual(secondQuery, firstQuery)
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
