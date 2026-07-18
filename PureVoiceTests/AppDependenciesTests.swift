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

    func testImportDependenciesPersistAndClearRestorableImportState() async throws {
        let suiteName = "AppDependenciesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let restorer = AppStateRestorer(defaults: defaults)
        let source = temporaryDirectory.appendingPathComponent("restorable.txt")
        try Data("正文".utf8).write(to: source)
        let repository = RecordingAppRepository()
        let converter = WaitingAppConverter()
        let dependencies = await AppDependencies.make(
            repository: repository,
            fileStore: try BookFileStore(applicationSupportRoot: temporaryDirectory),
            converter: converter,
            publicationOpener: StaticAppPublicationOpener(),
            appStateRestorer: restorer
        )

        let importTask = Task { try await dependencies.importCoordinator.importBook(from: source) }
        await converter.waitUntilConversionStarts()

        let interruptedPlan = restorer.restoreLaunchState()

        await converter.finish()
        try await importTask.value

        guard case let .markImportFailed(_, originalFileURL, error) = interruptedPlan else {
            return XCTFail("Expected an in-flight import to be restorable as a failed import")
        }
        XCTAssertEqual(originalFileURL.lastPathComponent, "original.txt")
        XCTAssertEqual(error, .importInterrupted)
        XCTAssertNil(restorer.restoreLaunchState())
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

private actor WaitingAppConverter: CanonicalPublicationConverting {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    func convert(
        originalURL: URL,
        format: BookFormat,
        suggestedTitle: String,
        destinationURL: URL
    ) async throws {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
        try Data("epub".utf8).write(to: destinationURL)
    }

    func waitUntilConversionStarts() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private struct StaticAppPublicationOpener: PublicationOpening {
    func openPublication(at canonicalURL: URL) async throws -> PublicationMetadata {
        PublicationMetadata(title: "导入书", author: "作者", coverURL: nil)
    }
}
