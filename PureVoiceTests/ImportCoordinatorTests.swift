import XCTest
@testable import PureVoice

@MainActor
final class ImportCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!
    nonisolated(unsafe) private var fileStore: BookFileStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileStore = try BookFileStore(applicationSupportRoot: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        fileStore = nil
        temporaryDirectory = nil
    }

    func testSuccessHasStrictStateOrderAndSavesMetadataLast() async throws {
        let source = try write(Data("text".utf8), named: "source.txt")
        let repository = RecordingRepository()
        let converter = RecordingConverter { original, format, destination in
            XCTAssertEqual(format, .txt)
            XCTAssertEqual(try Data(contentsOf: original), Data("text".utf8))
            try Data("epub".utf8).write(to: destination)
        }
        let opener = RecordingPublicationOpener(
            metadata: PublicationMetadata(title: "本地书", author: "作者", coverURL: nil)
        )
        var states: [ImportState] = []
        let coordinator = ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: converter,
            publicationOpener: opener,
            repository: repository,
            stateObserver: { states.append($0) }
        )

        try await coordinator.importBook(from: source)

        guard case let .completed(bookID) = coordinator.state else {
            return XCTFail("Unexpected final state: \(coordinator.state)")
        }
        XCTAssertEqual(states, [
            .copying,
            .detecting,
            .converting(.txt),
            .openingPublication,
            .completed(bookID)
        ])
        let fetchedBook = await repository.book(id: bookID)
        let saved = try XCTUnwrap(fetchedBook)
        XCTAssertEqual(saved.title, "本地书")
        XCTAssertEqual(saved.author, "作者")
        XCTAssertEqual(saved.format, .txt)
        XCTAssertEqual(saved.originalFileURL.lastPathComponent, "original.txt")
        XCTAssertEqual(saved.canonicalFileURL, fileStore.canonicalURL(for: bookID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.canonicalFileURL.path))
        let openCount = await opener.count()
        let saveCount = await repository.count()
        let deleteCount = await repository.deleteCountValue()
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(deleteCount, 0)
    }

    func testConversionFailurePreservesOriginalCleansCanonicalAndDoesNotSave() async throws {
        let source = try write(Data("text".utf8), named: "source.txt")
        let repository = RecordingRepository()
        let converter = RecordingConverter { _, _, destination in
            try Data("partial".utf8).write(to: destination)
            throw TestError.conversion
        }
        let coordinator = makeCoordinator(repository: repository, converter: converter)

        try await coordinator.importBook(from: source)

        guard case .failed(.convertFailed) = coordinator.state else {
            return XCTFail("Unexpected final state: \(coordinator.state)")
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: fileStore.booksRoot,
            includingPropertiesForKeys: nil
        )
        let bookDirectory = try XCTUnwrap(directories.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bookDirectory.appendingPathComponent("original.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookDirectory.appendingPathComponent("publication.epub").path))
        let saveCount = await repository.count()
        XCTAssertEqual(saveCount, 0)
    }

    func testDetectOpenAndSaveFailuresAreDistinctAndCleanCanonical() async throws {
        let unsupported = try write(Data("data".utf8), named: "source.pdf")
        let detectCoordinator = makeCoordinator(repository: RecordingRepository())
        try await detectCoordinator.importBook(from: unsupported)
        XCTAssertEqual(detectCoordinator.state, .failed(.unsupported))

        let source = try write(Data("text".utf8), named: "source.txt")
        let openRepository = RecordingRepository()
        let openCoordinator = makeCoordinator(
            repository: openRepository,
            opener: RecordingPublicationOpener(error: TestError.open)
        )
        try await openCoordinator.importBook(from: source)
        guard case .failed(.openFailed) = openCoordinator.state else {
            return XCTFail("Unexpected open state: \(openCoordinator.state)")
        }
        let openSaveCount = await openRepository.count()
        XCTAssertEqual(openSaveCount, 0)

        let saveRepository = RecordingRepository(saveError: TestError.save)
        let saveCoordinator = makeCoordinator(repository: saveRepository)
        try await saveCoordinator.importBook(from: source)
        guard case .failed(.saveFailed) = saveCoordinator.state else {
            return XCTFail("Unexpected save state: \(saveCoordinator.state)")
        }
        let failedSaveCount = await saveRepository.count()
        XCTAssertEqual(failedSaveCount, 1)
    }

    func testCopyErrorsMapToTooLargeAndOutOfSpaceWithoutStartingLaterStages() async {
        for (error, expected) in [
            (BookFileError.tooLarge(actualBytes: 251, maximumBytes: 250), ImportFailure.tooLarge),
            (BookFileError.outOfSpace, ImportFailure.outOfSpace)
        ] {
            let store = FailingImportFileStore(error: error)
            let converter = RecordingConverter()
            let coordinator = ImportCoordinator(
                fileStore: store,
                detector: BookFormatDetector(),
                converter: converter,
                publicationOpener: RecordingPublicationOpener(),
                repository: RecordingRepository()
            )

            try? await coordinator.importBook(from: URL(fileURLWithPath: "/tmp/source.txt"))

            XCTAssertEqual(coordinator.state, .failed(expected))
            let convertCount = await converter.count()
            XCTAssertEqual(convertCount, 0)
        }
    }

    func testCancellationAtBarrierIsDeterministicAndSecondImportDoesNotInterleave() async throws {
        let firstSource = try write(Data("first".utf8), named: "first.txt")
        let secondSource = try write(Data("second".utf8), named: "second.txt")
        let barrier = ConversionBarrier()
        let converter = RecordingConverter { _, _, destination in
            await barrier.waitUntilReleased()
            try Task.checkCancellation()
            try Data("epub".utf8).write(to: destination)
        }
        var states: [ImportState] = []
        let coordinator = makeCoordinator(
            repository: RecordingRepository(),
            converter: converter,
            stateObserver: { states.append($0) }
        )

        let firstTask = Task { try? await coordinator.importBook(from: firstSource) }
        await barrier.waitUntilEntered()
        do {
            try await coordinator.importBook(from: secondSource)
            XCTFail("A concurrent import should be rejected")
        } catch {
            XCTAssertEqual(error as? ImportCoordinatorError, .importInProgress)
        }
        firstTask.cancel()
        await barrier.release()
        await firstTask.value

        XCTAssertEqual(coordinator.state, .failed(.cancelled))
        let convertCount = await converter.count()
        XCTAssertEqual(convertCount, 1)
        XCTAssertEqual(states.filter { $0 == .copying }.count, 1)
        XCTAssertFalse(states.contains { state in
            if case .completed = state { return true }
            return false
        })
    }

    func testCancellationDuringSaveRollsBackSavedBookAndCleansCanonical() async throws {
        let source = try write(Data("text".utf8), named: "save-cancel.txt")
        let repository = SaveBarrierRepository()
        var states: [ImportState] = []
        let coordinator = ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: RecordingConverter(),
            publicationOpener: RecordingPublicationOpener(),
            repository: repository,
            stateObserver: { states.append($0) }
        )

        let importTask = Task { try? await coordinator.importBook(from: source) }
        await repository.waitUntilSaveEntered()
        let recordedBook = await repository.recordedBook()
        let savedBook = try XCTUnwrap(recordedBook)
        importTask.cancel()
        await repository.releaseSave()
        await importTask.value

        XCTAssertEqual(coordinator.state, .failed(.cancelled))
        let rolledBackBook = try await repository.book(id: savedBook.id)
        XCTAssertNil(rolledBackBook)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedBook.originalFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedBook.canonicalFileURL.path))
        XCTAssertFalse(states.contains { state in
            if case .completed = state { return true }
            return false
        })
    }

    func testCancellationDuringSaveReportsRollbackFailureAndKeepsRecordVisible() async throws {
        let source = try write(Data("text".utf8), named: "rollback-failure.txt")
        let repository = SaveBarrierRepository(deleteError: TestError.rollback)
        var states: [ImportState] = []
        let coordinator = ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: RecordingConverter(),
            publicationOpener: RecordingPublicationOpener(),
            repository: repository,
            stateObserver: { states.append($0) }
        )

        let importTask = Task { try? await coordinator.importBook(from: source) }
        await repository.waitUntilSaveEntered()
        let recordedBook = await repository.recordedBook()
        let savedBook = try XCTUnwrap(recordedBook)
        importTask.cancel()
        await repository.releaseSave()
        await importTask.value

        guard case let .failed(.saveFailed(message)) = coordinator.state else {
            return XCTFail("Unexpected state: \(coordinator.state)")
        }
        XCTAssertTrue(message.contains("回滚失败"))
        let remainingBook = try await repository.book(id: savedBook.id)
        XCTAssertEqual(remainingBook, savedBook)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedBook.originalFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedBook.canonicalFileURL.path))
        XCTAssertFalse(states.contains { state in
            if case .completed = state { return true }
            return false
        })
    }

    func testCopyRunsOffMainThread() async throws {
        let source = try write(Data("text".utf8), named: "thread-probe.txt")
        let store = ThreadProbeFileStore(root: temporaryDirectory)
        let coordinator = ImportCoordinator(
            fileStore: store,
            detector: BookFormatDetector(),
            converter: RecordingConverter(),
            publicationOpener: RecordingPublicationOpener(),
            repository: RecordingRepository()
        )

        try await coordinator.importBook(from: source)

        XCTAssertEqual(store.copyRanOnMainThread, false)
    }

    func testSaveThatCommitsThenThrowsIsRolledBackBeforeCanonicalCleanup() async throws {
        let source = try write(Data("text".utf8), named: "commit-then-throw.txt")
        let repository = CommitThenThrowRepository()
        let coordinator = ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: RecordingConverter(),
            publicationOpener: RecordingPublicationOpener(),
            repository: repository
        )

        try await coordinator.importBook(from: source)

        guard case .failed(.saveFailed) = coordinator.state else {
            return XCTFail("Unexpected state: \(coordinator.state)")
        }
        let recordedValue = await repository.recordedBook()
        let recordedBook = try XCTUnwrap(recordedValue)
        let storedBook = await repository.storedBook(id: recordedBook.id)
        XCTAssertNil(storedBook)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedBook.originalFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedBook.canonicalFileURL.path))
    }

    func testRollbackQueryFailurePreservesRecordAndCanonical() async throws {
        let source = try write(Data("text".utf8), named: "query-failure.txt")
        let repository = SaveBarrierRepository(bookQueryError: TestError.rollback)
        let coordinator = ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: RecordingConverter(),
            publicationOpener: RecordingPublicationOpener(),
            repository: repository
        )

        let importTask = Task { try? await coordinator.importBook(from: source) }
        await repository.waitUntilSaveEntered()
        let recordedValue = await repository.recordedBook()
        let recordedBook = try XCTUnwrap(recordedValue)
        importTask.cancel()
        await repository.releaseSave()
        await importTask.value

        guard case let .failed(.saveFailed(message)) = coordinator.state else {
            return XCTFail("Unexpected state: \(coordinator.state)")
        }
        XCTAssertTrue(message.contains("回滚失败"))
        let recordRemains = await repository.containsStoredBook(id: recordedBook.id)
        XCTAssertTrue(recordRemains)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedBook.originalFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedBook.canonicalFileURL.path))
    }

    func testCanonicalCleanupFailureOverridesOriginalFailure() async throws {
        let source = try write(Data("text".utf8), named: "cleanup-failure.txt")
        let cleanupFailingStore = CleanupFailingFileStore(base: fileStore)
        let converter = RecordingConverter { _, _, destination in
            try Data("partial".utf8).write(to: destination)
            throw TestError.conversion
        }
        let repository = RecordingRepository()
        let coordinator = ImportCoordinator(
            fileStore: cleanupFailingStore,
            detector: BookFormatDetector(),
            converter: converter,
            publicationOpener: RecordingPublicationOpener(),
            repository: repository
        )

        try await coordinator.importBook(from: source)

        guard case let .failed(.cleanupFailed(message)) = coordinator.state else {
            return XCTFail("Unexpected state: \(coordinator.state)")
        }
        XCTAssertTrue(message.contains("清理"))
        let originalURL = try XCTUnwrap(cleanupFailingStore.importedOriginalURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: originalURL.deletingLastPathComponent()
                    .appendingPathComponent("publication.epub").path
            )
        )
        let books = await repository.allBooks()
        XCTAssertTrue(books.isEmpty)
    }

    func testConcreteConversionErrorWinsWhenTaskIsAlreadyCancelled() async throws {
        let source = try write(Data("text".utf8), named: "cancelled-conversion-error.txt")
        let barrier = ConversionBarrier()
        let converter = RecordingConverter { _, _, destination in
            try Data("partial".utf8).write(to: destination)
            await barrier.waitUntilReleased()
            throw TestError.conversion
        }
        let coordinator = makeCoordinator(
            repository: RecordingRepository(),
            converter: converter
        )

        let importTask = Task { try? await coordinator.importBook(from: source) }
        await barrier.waitUntilEntered()
        importTask.cancel()
        await barrier.release()
        await importTask.value

        guard case .failed(.convertFailed) = coordinator.state else {
            return XCTFail("Unexpected state: \(coordinator.state)")
        }
    }

    func testCleanupFailureWinsOverConcreteErrorWhenTaskIsCancelled() async throws {
        let source = try write(Data("text".utf8), named: "cancelled-cleanup-error.txt")
        let barrier = ConversionBarrier()
        let cleanupFailingStore = CleanupFailingFileStore(base: fileStore)
        let converter = RecordingConverter { _, _, destination in
            try Data("partial".utf8).write(to: destination)
            await barrier.waitUntilReleased()
            throw TestError.conversion
        }
        let coordinator = ImportCoordinator(
            fileStore: cleanupFailingStore,
            detector: BookFormatDetector(),
            converter: converter,
            publicationOpener: RecordingPublicationOpener(),
            repository: RecordingRepository()
        )

        let importTask = Task { try? await coordinator.importBook(from: source) }
        await barrier.waitUntilEntered()
        importTask.cancel()
        await barrier.release()
        await importTask.value

        guard case .failed(.cleanupFailed) = coordinator.state else {
            return XCTFail("Unexpected state: \(coordinator.state)")
        }
        let originalURL = try XCTUnwrap(cleanupFailingStore.importedOriginalURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: originalURL.deletingLastPathComponent()
                    .appendingPathComponent("publication.epub").path
            )
        )
    }

    private func makeCoordinator(
        repository: RecordingRepository,
        converter: RecordingConverter = RecordingConverter(),
        opener: RecordingPublicationOpener = RecordingPublicationOpener(),
        stateObserver: @escaping @MainActor (ImportState) -> Void = { _ in }
    ) -> ImportCoordinator {
        ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: converter,
            publicationOpener: opener,
            repository: repository,
            stateObserver: stateObserver
        )
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

private enum TestError: Error {
    case conversion
    case open
    case save
    case rollback
    case cleanup
}

private actor RecordingConverter: CanonicalPublicationConverting {
    typealias Operation = @Sendable (URL, BookFormat, URL) async throws -> Void
    private let operation: Operation
    private(set) var convertCount = 0

    init(operation: @escaping Operation = { _, _, destination in
        try Data("epub".utf8).write(to: destination)
    }) {
        self.operation = operation
    }

    func convert(originalURL: URL, format: BookFormat, destinationURL: URL) async throws {
        convertCount += 1
        try await operation(originalURL, format, destinationURL)
    }

    func count() -> Int { convertCount }
}

private actor RecordingPublicationOpener: PublicationOpening {
    private let metadata: PublicationMetadata
    private let error: Error?
    private(set) var openCount = 0

    init(
        metadata: PublicationMetadata = PublicationMetadata(title: "Title", author: nil, coverURL: nil),
        error: Error? = nil
    ) {
        self.metadata = metadata
        self.error = error
    }

    func openPublication(at canonicalURL: URL) async throws -> PublicationMetadata {
        openCount += 1
        if let error { throw error }
        return metadata
    }

    func count() -> Int { openCount }
}

private actor RecordingRepository: BookRepository {
    private var books: [UUID: Book] = [:]
    private let saveError: Error?
    private(set) var saveCount = 0
    private var deleteCount = 0

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    func allBooks() -> [Book] { Array(books.values) }
    func recentBooks(limit: Int) -> [Book] { Array(books.values.prefix(limit)) }
    func book(id: UUID) -> Book? { books[id] }
    func save(_ book: Book) throws {
        saveCount += 1
        if let saveError { throw saveError }
        books[book.id] = book
    }
    func delete(id: UUID) {
        deleteCount += 1
        books[id] = nil
    }
    func count() -> Int { saveCount }
    func deleteCountValue() -> Int { deleteCount }
}

private actor SaveBarrierRepository: BookRepository {
    private var books: [UUID: Book] = [:]
    private var lastSavedBook: Book?
    private let deleteError: Error?
    private let bookQueryError: Error?
    private var saveEntered = false
    private var saveReleased = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(deleteError: Error? = nil, bookQueryError: Error? = nil) {
        self.deleteError = deleteError
        self.bookQueryError = bookQueryError
    }

    func allBooks() -> [Book] { Array(books.values) }
    func recentBooks(limit: Int) -> [Book] { Array(books.values.prefix(limit)) }
    func book(id: UUID) throws -> Book? {
        if let bookQueryError { throw bookQueryError }
        return books[id]
    }

    func save(_ book: Book) async {
        books[book.id] = book
        lastSavedBook = book
        saveEntered = true
        enteredContinuations.forEach { $0.resume() }
        enteredContinuations.removeAll()
        if saveReleased { return }
        await withCheckedContinuation { releaseContinuations.append($0) }
    }

    func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        books[id] = nil
    }

    func waitUntilSaveEntered() async {
        if saveEntered { return }
        await withCheckedContinuation { enteredContinuations.append($0) }
    }

    func releaseSave() {
        saveReleased = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }

    func recordedBook() -> Book? { lastSavedBook }
    func containsStoredBook(id: UUID) -> Bool { books[id] != nil }
}

private actor CommitThenThrowRepository: BookRepository {
    private var books: [UUID: Book] = [:]
    private var lastSavedBook: Book?

    func allBooks() -> [Book] { Array(books.values) }
    func recentBooks(limit: Int) -> [Book] { Array(books.values.prefix(limit)) }
    func book(id: UUID) -> Book? { books[id] }
    func save(_ book: Book) throws {
        books[book.id] = book
        lastSavedBook = book
        throw TestError.save
    }
    func delete(id: UUID) { books[id] = nil }
    func recordedBook() -> Book? { lastSavedBook }
    func storedBook(id: UUID) -> Book? { books[id] }
}

private final class ThreadProbeFileStore: ImportFileStoring, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var copyMainThreadValue: Bool?

    init(root: URL) {
        self.root = root.appendingPathComponent("ThreadProbe-\(UUID().uuidString)")
    }

    var copyRanOnMainThread: Bool? {
        lock.withLock { copyMainThreadValue }
    }

    func importOriginal(from sourceURL: URL, bookID: UUID) throws -> URL {
        lock.withLock { copyMainThreadValue = Thread.isMainThread }
        let destination = root
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
            .appendingPathComponent("original.\(sourceURL.pathExtension.lowercased())")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func canonicalURL(for bookID: UUID) -> URL {
        root.appendingPathComponent(bookID.uuidString).appendingPathComponent("publication.epub")
    }

    func removeCanonicalFile(bookID: UUID) throws {
        let url = canonicalURL(for: bookID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private final class CleanupFailingFileStore: ImportFileStoring, @unchecked Sendable {
    let base: BookFileStore
    private let lock = NSLock()
    private var importedOriginal: URL?

    init(base: BookFileStore) {
        self.base = base
    }

    var importedOriginalURL: URL? { lock.withLock { importedOriginal } }

    func importOriginal(from sourceURL: URL, bookID: UUID) throws -> URL {
        let url = try base.importOriginal(from: sourceURL, bookID: bookID)
        lock.withLock {
            importedOriginal = url
        }
        return url
    }

    func canonicalURL(for bookID: UUID) -> URL { base.canonicalURL(for: bookID) }

    func removeCanonicalFile(bookID: UUID) throws {
        throw TestError.cleanup
    }
}

private struct FailingImportFileStore: ImportFileStoring {
    let error: Error

    func importOriginal(from sourceURL: URL, bookID: UUID) throws -> URL { throw error }
    func canonicalURL(for bookID: UUID) -> URL { URL(fileURLWithPath: "/tmp/\(bookID)/publication.epub") }
    func removeCanonicalFile(bookID: UUID) throws {}
}

private actor ConversionBarrier {
    private var entered = false
    private var released = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredContinuations.append($0) }
    }

    func waitUntilReleased() async {
        entered = true
        enteredContinuations.forEach { $0.resume() }
        enteredContinuations.removeAll()
        if released { return }
        await withCheckedContinuation { releaseContinuations.append($0) }
    }

    func release() {
        released = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }
}
