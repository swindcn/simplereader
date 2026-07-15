import enum ReadiumShared.AnyURL
import struct ReadiumShared.Locator
import struct ReadiumShared.MediaType
import ReadiumNavigator
import XCTest
@testable import PureVoice

@MainActor
final class ReaderViewModelTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testOpenRestoresSavedLocatorAndPublishesInitialChapterFocus() async throws {
        let epubURL = try copyFixture()
        let position = ReadingPosition(
            href: "EPUB/chapter-2.xhtml",
            locationsJSON: "{\"progression\":0.2,\"totalProgression\":0.7}",
            progression: 0.7
        )
        let book = Book.fixture(canonicalFileURL: epubURL, position: position)
        let viewModel = ReaderViewModel(book: book, repository: InMemoryBookRepository(books: [book]))

        await viewModel.open()

        XCTAssertEqual(viewModel.initialLocator?.href.string, "EPUB/chapter-2.xhtml")
        XCTAssertEqual(viewModel.chapterTitle, "第二章 继续")
        XCTAssertEqual(viewModel.chapterFocusGeneration, 1)
        XCTAssertNotNil(viewModel.openedPublication)
        XCTAssertTrue(viewModel.isReady)
    }

    func testInvalidSavedPositionIsIgnoredUntilNavigatorProvidesAValidReplacement() async throws {
        let epubURL = try copyFixture()
        let invalidPosition = ReadingPosition(
            href: "EPUB/missing.xhtml",
            locationsJSON: "{\"progression\":0.5}",
            progression: 0.5
        )
        let book = Book.fixture(canonicalFileURL: epubURL, position: invalidPosition)
        let repository = AtomicPositionBookRepository(book: book)
        let viewModel = ReaderViewModel(book: book, repository: repository, persistenceDelay: 60)

        await viewModel.open()

        XCTAssertNotNil(viewModel.openedPublication)
        XCTAssertNil(viewModel.initialLocator)
        XCTAssertEqual(viewModel.chapterTitle, "第一章 起点")
        XCTAssertEqual(viewModel.errorMessage, "上次阅读位置已失效，已从书首开始。")
        let openingUpdates = await repository.positionUpdates
        let openingPosition = await repository.currentBook.position
        XCTAssertEqual(openingUpdates, [])
        XCTAssertEqual(openingPosition, invalidPosition)

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.25))
        let flushSucceeded = await viewModel.flushProgress()

        let updates = await repository.positionUpdates
        let persistedProgression = await repository.currentBook.position?.progression
        let replacement = try XCTUnwrap(updates.first ?? nil)
        XCTAssertTrue(flushSucceeded)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(replacement.href, "EPUB/chapter-1.xhtml")
        XCTAssertEqual(persistedProgression, 0.25)
    }

    func testLocatorChangesAreCoalescedUntilFlushAndPersistOnlyLatestPosition() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let repository = RecordingBookRepository(book: book)
        let viewModel = ReaderViewModel(
            book: book,
            repository: repository,
            persistenceDelay: 60
        )
        await viewModel.open()
        let first = makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.1)
        let latest = makeLocator(href: "EPUB/chapter-2.xhtml", progression: 0.8)

        viewModel.receive(locator: first)
        viewModel.receive(locator: latest)

        let saveCountBeforeFlush = await repository.saveCount
        XCTAssertEqual(saveCountBeforeFlush, 0)
        await viewModel.flushProgress()

        let saveCountAfterFlush = await repository.saveCount
        let persistedBook = await repository.savedBook
        XCTAssertEqual(saveCountAfterFlush, 1)
        let saved = try XCTUnwrap(persistedBook)
        XCTAssertEqual(saved.position?.href, "EPUB/chapter-2.xhtml")
        XCTAssertEqual(saved.position?.progression, 0.8)
    }

    func testLatestProgressIsPersistedAutomaticallyAfterDebounceDelay() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let repository = RecordingBookRepository(book: book)
        let viewModel = ReaderViewModel(book: book, repository: repository, persistenceDelay: 0.03)
        await viewModel.open()

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.2))
        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-2.xhtml", progression: 0.75))
        try await Task.sleep(nanoseconds: 100_000_000)

        let saveCount = await repository.saveCount
        let savedBook = await repository.savedBook
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(savedBook?.position?.href, "EPUB/chapter-2.xhtml")
        XCTAssertEqual(savedBook?.position?.progression, 0.75)
    }

    func testFlushSerializesInFlightSaveAndDrainsLatestLocator() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let repository = ControlledSaveBookRepository(book: book, outcomes: [.success, .success])
        let viewModel = ReaderViewModel(book: book, repository: repository, persistenceDelay: 60)
        await viewModel.open()

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.2))
        let firstFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(1)

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-2.xhtml", progression: 0.8))
        let joinedFlush = Task { await viewModel.flushProgress() }
        for _ in 0..<20 { await Task.yield() }

        let startsWhileFirstIsBlocked = await repository.startedCount
        let maximumConcurrency = await repository.maximumConcurrentSaveCount
        XCTAssertEqual(startsWhileFirstIsBlocked, 1)
        XCTAssertEqual(maximumConcurrency, 1)

        await repository.releaseNextSave()
        await repository.waitUntilSaveStarts(2)
        await repository.releaseNextSave()
        await firstFlush.value
        await joinedFlush.value

        let savedProgressions = await repository.savedBooks.compactMap { $0.position?.progression }
        let finalMaximumConcurrency = await repository.maximumConcurrentSaveCount
        XCTAssertEqual(savedProgressions, [0.2, 0.8])
        XCTAssertEqual(finalMaximumConcurrency, 1)
    }

    func testFailedOldSaveDoesNotOverwriteNewerPendingLocator() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let repository = ControlledSaveBookRepository(book: book, outcomes: [.failure, .success])
        let viewModel = ReaderViewModel(book: book, repository: repository, persistenceDelay: 60)
        await viewModel.open()

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.2))
        let failedFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(1)
        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-2.xhtml", progression: 0.85))
        await repository.releaseNextSave()
        await failedFlush.value

        let retry = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(2)
        await repository.releaseNextSave()
        await retry.value

        let attemptedProgressions = await repository.attemptedBooks.compactMap { $0.position?.progression }
        let savedProgressions = await repository.savedBooks.compactMap { $0.position?.progression }
        XCTAssertEqual(attemptedProgressions, [0.2, 0.85])
        XCTAssertEqual(savedProgressions, [0.85])
    }

    func testFailedSaveWithoutNewLocatorRemainsPendingForRetry() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let repository = ControlledSaveBookRepository(book: book, outcomes: [.failure, .success])
        let viewModel = ReaderViewModel(book: book, repository: repository, persistenceDelay: 60)
        await viewModel.open()

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.4))
        let failedFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(1)
        await repository.releaseNextSave()
        await failedFlush.value

        let retry = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(2)
        await repository.releaseNextSave()
        await retry.value

        let attemptedProgressions = await repository.attemptedBooks.compactMap { $0.position?.progression }
        let savedProgressions = await repository.savedBooks.compactMap { $0.position?.progression }
        XCTAssertEqual(attemptedProgressions, [0.4, 0.4])
        XCTAssertEqual(savedProgressions, [0.4])
    }

    func testFlushOutcomeStaysFailedUntilPendingPositionIsRetriedSuccessfully() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let repository = ControlledSaveBookRepository(book: book, outcomes: [.failure, .success])
        let viewModel = ReaderViewModel(book: book, repository: repository, persistenceDelay: 60)
        await viewModel.open()
        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.45))

        let firstFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(1)
        await repository.releaseNextSave()
        let firstOutcome = await firstFlush.value

        let retryFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(2)
        await repository.releaseNextSave()
        let retryOutcome = await retryFlush.value

        XCTAssertFalse(firstOutcome)
        XCTAssertTrue(retryOutcome)
    }

    func testProgressUpdateDoesNotRollbackBookFieldsChangedWhileReading() async throws {
        let epubURL = try copyFixture()
        let openedBook = Book.fixture(
            title: "打开时书名",
            canonicalFileURL: epubURL,
            lastOpenedAt: Date(timeIntervalSince1970: 10)
        )
        let repository = AtomicPositionBookRepository(book: openedBook)
        let viewModel = ReaderViewModel(book: openedBook, repository: repository, persistenceDelay: 60)
        await viewModel.open()
        var editedBook = openedBook
        editedBook.title = "阅读期间重命名"
        editedBook.lastOpenedAt = Date(timeIntervalSince1970: 99)
        await repository.replace(with: editedBook)

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-2.xhtml", progression: 0.9))
        let outcome = await viewModel.flushProgress()

        let persisted = await repository.currentBook
        XCTAssertTrue(outcome)
        XCTAssertEqual(persisted.title, "阅读期间重命名")
        XCTAssertEqual(persisted.lastOpenedAt, Date(timeIntervalSince1970: 99))
        XCTAssertEqual(persisted.position?.progression, 0.9)
    }

    func testChapterFocusChangesOncePerChapterRatherThanForEveryProgressUpdate() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let viewModel = ReaderViewModel(book: book, repository: InMemoryBookRepository(books: [book]))
        await viewModel.open()
        let openingGeneration = viewModel.chapterFocusGeneration

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.2))
        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-1.xhtml", progression: 0.4))
        XCTAssertEqual(viewModel.chapterFocusGeneration, openingGeneration)

        viewModel.receive(locator: makeLocator(href: "EPUB/chapter-2.xhtml", progression: 0.6))
        XCTAssertEqual(viewModel.chapterTitle, "第二章 继续")
        XCTAssertEqual(viewModel.chapterFocusGeneration, openingGeneration + 1)
    }

    func testTableOfContentsIsFlattenedAndSelectionCreatesNavigationRequest() async throws {
        let epubURL = try copyFixture()
        let book = Book.fixture(canonicalFileURL: epubURL)
        let viewModel = ReaderViewModel(book: book, repository: InMemoryBookRepository(books: [book]))
        await viewModel.open()

        XCTAssertEqual(viewModel.tableOfContents.map(\.title), ["第一章 起点", "第一节", "第二章 继续"])
        XCTAssertEqual(viewModel.tableOfContents.map(\.level), [0, 1, 0])

        viewModel.isTableOfContentsPresented = true
        viewModel.selectChapter(viewModel.tableOfContents[2])

        XCTAssertEqual(viewModel.navigationRequest?.href, "EPUB/chapter-2.xhtml")
        XCTAssertFalse(viewModel.isTableOfContentsPresented)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFlattenedTableOfContentsUsesTreePathForDuplicateHREFIdentity() {
        let entries = ReaderViewModel.flatten([
            PublicationTOCItem(title: "镜像一", href: "same.xhtml"),
            PublicationTOCItem(title: "镜像二", href: "same.xhtml")
        ])

        XCTAssertEqual(entries.map(\.id), ["0", "1"])
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        XCTAssertEqual(entries.map(\.href), ["same.xhtml", "same.xhtml"])
    }

    func testEPUBPreferencesRoundTripThroughUserDefaultsStore() throws {
        let suiteName = "ReaderEPUBPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReaderEPUBPreferencesStore(defaults: defaults)

        store.save(EPUBPreferences(fontSize: 1.25, lineHeight: 1.7, scroll: true, theme: .sepia))
        let restored = store.load()

        XCTAssertEqual(restored.fontSize, 1.25)
        XCTAssertEqual(restored.lineHeight, 1.7)
        XCTAssertEqual(restored.scroll, true)
        XCTAssertEqual(restored.theme, .sepia)
    }

    private func makeLocator(href: String, progression: Double) -> Locator {
        Locator(
            href: AnyURL(string: href)!,
            mediaType: .xhtml,
            locations: .init(progression: progression, totalProgression: progression)
        )
    }

    private func copyFixture() throws -> URL {
        let source = Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub")!
        let destination = temporaryDirectory.appendingPathComponent("minimal.epub")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

private actor RecordingBookRepository: BookRepository {
    private(set) var savedBook: Book?
    private(set) var saveCount = 0
    private var bookValue: Book

    init(book: Book) {
        bookValue = book
    }

    func allBooks() -> [Book] { [bookValue] }
    func recentBooks(limit: Int) -> [Book] { limit > 0 ? [bookValue] : [] }
    func book(id: UUID) -> Book? { id == bookValue.id ? bookValue : nil }

    func save(_ book: Book) {
        bookValue = book
        savedBook = book
        saveCount += 1
    }

    func updatePosition(id: UUID, position: ReadingPosition?) {
        guard bookValue.id == id else { return }
        bookValue.position = position
        savedBook = bookValue
        saveCount += 1
    }

    func delete(id: UUID) {}
}

private actor ControlledSaveBookRepository: BookRepository {
    enum Outcome {
        case success
        case failure
    }

    private var bookValue: Book
    private var outcomes: [Outcome]
    private var activeSaveCount = 0
    private(set) var maximumConcurrentSaveCount = 0
    private(set) var attemptedBooks: [Book] = []
    private(set) var savedBooks: [Book] = []
    private var saveContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var startedCount: Int { attemptedBooks.count }

    init(book: Book, outcomes: [Outcome]) {
        bookValue = book
        self.outcomes = outcomes
    }

    func allBooks() -> [Book] { [bookValue] }
    func recentBooks(limit: Int) -> [Book] { limit > 0 ? [bookValue] : [] }
    func book(id: UUID) -> Book? { id == bookValue.id ? bookValue : nil }

    func save(_ book: Book) async throws {
        attemptedBooks.append(book)
        activeSaveCount += 1
        maximumConcurrentSaveCount = max(maximumConcurrentSaveCount, activeSaveCount)
        resumeSatisfiedStartWaiters()

        await withCheckedContinuation { continuation in
            saveContinuations.append(continuation)
        }

        activeSaveCount -= 1
        let outcome = outcomes.isEmpty ? Outcome.success : outcomes.removeFirst()
        switch outcome {
        case .success:
            bookValue = book
            savedBooks.append(book)
        case .failure:
            throw ControlledSaveError.expected
        }
    }

    func updatePosition(id: UUID, position: ReadingPosition?) async throws {
        guard bookValue.id == id else { return }
        var updatedBook = bookValue
        updatedBook.position = position
        try await save(updatedBook)
    }

    func delete(id: UUID) {}

    func waitUntilSaveStarts(_ count: Int) async {
        guard attemptedBooks.count < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func releaseNextSave() {
        guard !saveContinuations.isEmpty else { return }
        saveContinuations.removeFirst().resume()
    }

    private func resumeSatisfiedStartWaiters() {
        let satisfied = startWaiters.filter { attemptedBooks.count >= $0.count }
        startWaiters.removeAll { attemptedBooks.count >= $0.count }
        satisfied.forEach { $0.continuation.resume() }
    }
}

private enum ControlledSaveError: Error {
    case expected
}

private actor AtomicPositionBookRepository: BookRepository {
    private(set) var currentBook: Book
    private(set) var positionUpdates: [ReadingPosition?] = []

    init(book: Book) { currentBook = book }
    func allBooks() -> [Book] { [currentBook] }
    func recentBooks(limit: Int) -> [Book] { limit > 0 ? [currentBook] : [] }
    func book(id: UUID) -> Book? { id == currentBook.id ? currentBook : nil }
    func save(_ book: Book) { currentBook = book }
    func updatePosition(id: UUID, position: ReadingPosition?) {
        guard currentBook.id == id else { return }
        positionUpdates.append(position)
        currentBook.position = position
    }
    func delete(id: UUID) {}
    func replace(with book: Book) { currentBook = book }
}
