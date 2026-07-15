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

    func delete(id: UUID) {}
}
