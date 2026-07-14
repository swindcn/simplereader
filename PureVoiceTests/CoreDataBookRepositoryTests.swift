import CoreData
import XCTest
@testable import PureVoice

final class CoreDataBookRepositoryTests: XCTestCase {
    func testSaveRoundTripsEveryBookField() async throws {
        let repository = try await makeRepository()
        let book = Book.fixture(
            title: "长标题",
            author: "作者",
            format: .mobi,
            originalFileURL: URL(fileURLWithPath: "/tmp/source/original.mobi"),
            canonicalFileURL: URL(fileURLWithPath: "/tmp/library/publication.epub"),
            coverFileURL: URL(fileURLWithPath: "/tmp/library/cover"),
            position: ReadingPosition(
                href: "OPS/chapter-3.xhtml#part",
                locationsJSON: #"{"position":42}"#,
                progression: 0.375
            ),
            lastOpenedAt: Date(timeIntervalSince1970: 222),
            createdAt: Date(timeIntervalSince1970: 111)
        )

        try await repository.save(book)

        let saved = try await repository.book(id: book.id)
        XCTAssertEqual(saved, book)
    }

    func testSaveUpsertsSameIDWithoutDuplicateAndReplacesOptionalFields() async throws {
        let repository = try await makeRepository()
        let original = Book.fixture(
            coverFileURL: URL(fileURLWithPath: "/tmp/cover"),
            position: ReadingPosition(href: "one.xhtml", progression: 0.1),
            lastOpenedAt: Date(timeIntervalSince1970: 10)
        )
        var replacement = original
        replacement.title = "替换后"
        replacement.author = "新作者"
        replacement.format = .txt
        replacement.originalFileURL = URL(fileURLWithPath: "/new/original.txt")
        replacement.canonicalFileURL = URL(fileURLWithPath: "/new/publication.epub")
        replacement.coverFileURL = nil
        replacement.position = nil
        replacement.lastOpenedAt = nil
        replacement.createdAt = Date(timeIntervalSince1970: 99)

        try await repository.save(original)
        try await repository.save(replacement)

        let books = try await repository.allBooks()
        XCTAssertEqual(books, [replacement])
    }

    func testAllAndRecentBooksMatchRepositoryOrderingContract() async throws {
        let repository = try await makeRepository()
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let recentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let invalidID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let sharedDate = Date(timeIntervalSinceReferenceDate: 10)

        try await repository.save(.fixture(id: secondID, createdAt: sharedDate))
        try await repository.save(.fixture(id: firstID, createdAt: sharedDate))
        try await repository.save(.fixture(
            id: recentID,
            lastOpenedAt: Date(timeIntervalSinceReferenceDate: 30),
            createdAt: Date(timeIntervalSinceReferenceDate: 20)
        ))
        try await repository.save(.fixture(
            id: invalidID,
            lastOpenedAt: Date(timeIntervalSinceReferenceDate: .nan),
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)
        ))

        let allIDs = try await repository.allBooks().map(\.id)
        let recentIDs = try await repository.recentBooks(limit: 3).map(\.id)
        let empty = try await repository.recentBooks(limit: 0)
        let negative = try await repository.recentBooks(limit: -1)
        XCTAssertEqual(allIDs, [recentID, firstID, secondID, invalidID])
        XCTAssertEqual(recentIDs, [recentID, firstID, secondID])
        XCTAssertEqual(empty, [])
        XCTAssertEqual(negative, [])
    }

    func testDeleteIsIdempotentAndRemovesBook() async throws {
        let repository = try await makeRepository()
        let book = Book.fixture()
        try await repository.save(book)

        try await repository.delete(id: book.id)
        try await repository.delete(id: book.id)

        let deleted = try await repository.book(id: book.id)
        XCTAssertNil(deleted)
    }

    func testCorruptRowsThrowClearMappingErrors() async throws {
        let persistence = try await makePersistence()
        let repository = CoreDataBookRepository(container: persistence.container)
        let context = persistence.container.newBackgroundContext()
        try await context.perform {
            let object = NSEntityDescription.insertNewObject(forEntityName: "BookEntity", into: context)
            object.setValue(UUID(), forKey: "id")
            object.setValue("Title", forKey: "title")
            object.setValue("Author", forKey: "author")
            object.setValue("pdf", forKey: "format")
            object.setValue(URL(fileURLWithPath: "/tmp/original.pdf"), forKey: "originalFileURL")
            object.setValue(URL(fileURLWithPath: "/tmp/publication.epub"), forKey: "canonicalFileURL")
            object.setValue(Date(), forKey: "createdAt")
            try context.save()
        }

        do {
            _ = try await repository.allBooks()
            XCTFail("Expected an unknown-format mapping error")
        } catch let error as CoreDataBookRepositoryError {
            XCTAssertEqual(error, .unknownFormat("pdf"))
        }
    }

    func testCorruptPositionJSONThrowsClearMappingError() async throws {
        let persistence = try await makePersistence()
        let repository = CoreDataBookRepository(container: persistence.container)
        let book = Book.fixture()
        try await repository.save(book)
        let context = persistence.container.newBackgroundContext()
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
            let object = try XCTUnwrap(context.fetch(request).first)
            object.setValue(Data("not json".utf8), forKey: "position")
            try context.save()
        }

        do {
            _ = try await repository.book(id: book.id)
            XCTFail("Expected a corrupt-position mapping error")
        } catch let error as CoreDataBookRepositoryError {
            XCTAssertEqual(error, .invalidPositionData)
        }
    }

    private func makeRepository() async throws -> CoreDataBookRepository {
        let persistence = try await makePersistence()
        return CoreDataBookRepository(container: persistence.container)
    }

    private func makePersistence() async throws -> PersistenceController {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return try await PersistenceController(storeDescription: description)
    }
}
