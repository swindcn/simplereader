import CoreData
import XCTest
@testable import PureVoice

final class AppDependenciesTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDependenciesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testProductionDependenciesUseCoreDataRepositoryAndImportCoordinator() async throws {
        let persistence = try await PersistenceController(storeDescription: Self.inMemoryStoreDescription())
        let fileStore = try BookFileStore(applicationSupportRoot: temporaryDirectory)

        let dependencies = await AppDependencies.production(
            persistence: persistence,
            fileStore: fileStore
        )

        await MainActor.run {
            XCTAssertTrue(dependencies.repository is CoreDataBookRepository)
            XCTAssertNotNil(dependencies.importCoordinator)
            XCTAssertEqual(dependencies.libraryRefresh.generation, 0)
        }
    }

    func testSuccessfulImportTriggersLibraryRefreshSignal() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("正文".utf8).write(to: source)
        let repository = RecordingAppRepository()
        let fileStore = try BookFileStore(applicationSupportRoot: temporaryDirectory)
        let dependencies = await AppDependencies.make(
            repository: repository,
            fileStore: fileStore,
            converter: WritingAppConverter(),
            publicationOpener: StaticAppPublicationOpener()
        )

        try await dependencies.importCoordinator.importBook(from: source)

        let generation = await dependencies.libraryRefresh.generation
        XCTAssertEqual(generation, 1)
        let saveCount = await repository.count()
        XCTAssertEqual(saveCount, 1)
    }

    private static func inMemoryStoreDescription() -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        return description
    }
}

private actor RecordingAppRepository: BookRepository {
    private(set) var saveCount = 0
    private var books: [UUID: Book] = [:]

    func allBooks() -> [Book] { Array(books.values) }
    func recentBooks(limit: Int) -> [Book] { Array(books.values.prefix(limit)) }
    func book(id: UUID) -> Book? { books[id] }
    func save(_ book: Book) {
        saveCount += 1
        books[book.id] = book
    }
    func updatePosition(id: UUID, position: ReadingPosition?) {
        guard var book = books[id] else { return }
        book.position = position
        books[id] = book
    }
    func delete(id: UUID) { books[id] = nil }
    func count() -> Int { saveCount }
}

private struct WritingAppConverter: CanonicalPublicationConverting {
    func convert(
        originalURL: URL,
        format: BookFormat,
        suggestedTitle: String,
        destinationURL: URL
    ) async throws {
        try Data("epub".utf8).write(to: destinationURL)
    }
}

private struct StaticAppPublicationOpener: PublicationOpening {
    func openPublication(at canonicalURL: URL) async throws -> PublicationMetadata {
        PublicationMetadata(title: "导入书", author: "作者", coverURL: nil)
    }
}
