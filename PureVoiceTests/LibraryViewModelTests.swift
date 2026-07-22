import XCTest
import UIKit
@testable import PureVoice

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testLoadSeparatesContinueReadingFromThreeRecentBooks() async throws {
        let books = Self.books
        let repository = InMemoryBookRepository(books: books)
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.continueReadingBook?.id, books[0].id)
        XCTAssertEqual(viewModel.recentBooks.map(\.id), books.dropFirst().map(\.id))
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadPublishesAllShelfBooksInRecentOrder() async throws {
        let olderOpened = Book.fixture(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            title: "旧打开",
            lastOpenedAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newImport = Book.fixture(
            id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
            title: "新导入",
            lastOpenedAt: nil,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let recentOpened = Book.fixture(
            id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
            title: "最近打开",
            lastOpenedAt: Date(timeIntervalSince1970: 400),
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let repository = InMemoryBookRepository(books: [olderOpened, newImport, recentOpened])
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.continueReadingBook?.id, recentOpened.id)
        XCTAssertEqual(viewModel.shelfBooks.map(\.id), [newImport.id, olderOpened.id])
    }

    func testOpenPersistsLastOpenedDateAndDelegatesToReader() async throws {
        let book = Self.books[3]
        let repository = InMemoryBookRepository(books: [book])
        var openedBookID: UUID?
        let openedAt = Date(timeIntervalSince1970: 9_999)
        let viewModel = LibraryViewModel(
            repository: repository,
            now: { openedAt },
            onOpenBook: { openedBookID = $0.id }
        )

        await viewModel.open(book)

        let persistedBook = await repository.book(id: book.id)
        XCTAssertEqual(openedBookID, book.id)
        XCTAssertEqual(persistedBook?.lastOpenedAt, openedAt)
        XCTAssertEqual(viewModel.continueReadingBook?.id, book.id)
    }

    func testOpenPreservesNewerPersistedListeningProgressFromStaleShelfBook() async throws {
        let staleBook = Self.books[3]
        let latestPosition = ReadingPosition(href: "EPUB/chapter-3.xhtml", progression: 0.31)
        let repository = InMemoryBookRepository(books: [staleBook])
        try await repository.updatePosition(id: staleBook.id, position: latestPosition)
        var openedBook: Book?
        let viewModel = LibraryViewModel(
            repository: repository,
            now: { Date(timeIntervalSince1970: 9_999) },
            onOpenBook: { openedBook = $0 }
        )

        await viewModel.open(staleBook)

        let persistedBook = try await repository.book(id: staleBook.id)
        XCTAssertEqual(persistedBook?.position, latestPosition)
        XCTAssertEqual(openedBook?.position, latestPosition)
    }

    func testOpenCompletesAfterNewerLoadAndReconcilesShelf() async {
        let book = Self.books[3]
        let repository = DelayedSuccessfulMutationRepository(books: [book])
        var openedBook: Book?
        let openedAt = Date(timeIntervalSince1970: 9_999)
        let viewModel = LibraryViewModel(
            repository: repository,
            now: { openedAt },
            onOpenBook: { openedBook = $0 }
        )

        let open = Task { await viewModel.open(book) }
        await repository.waitUntilSaveStarts()
        await viewModel.load()
        await repository.finishSave()
        await open.value

        let persistedBook = await repository.book(id: book.id)
        XCTAssertEqual(openedBook?.id, book.id)
        XCTAssertEqual(persistedBook?.lastOpenedAt, openedAt)
        XCTAssertEqual(viewModel.continueReadingBook?.lastOpenedAt, openedAt)
    }

    func testRenamePersistsAndRefreshesBook() async throws {
        let book = Self.books[0]
        let repository = InMemoryBookRepository(books: [book])
        let viewModel = LibraryViewModel(repository: repository)
        await viewModel.load()

        await viewModel.rename(book, to: "新的书名")

        let persistedBook = await repository.book(id: book.id)
        XCTAssertEqual(persistedBook?.title, "新的书名")
        XCTAssertEqual(viewModel.continueReadingBook?.title, "新的书名")
    }

    func testRenameCompletesAfterNewerLoadAndReconcilesShelf() async {
        let book = Self.books[0]
        let repository = DelayedSuccessfulMutationRepository(books: [book])
        let viewModel = LibraryViewModel(repository: repository)

        let rename = Task { await viewModel.rename(book, to: "新的书名") }
        await repository.waitUntilSaveStarts()
        await viewModel.load()
        await repository.finishSave()
        await rename.value

        let persistedBook = await repository.book(id: book.id)
        XCTAssertEqual(persistedBook?.title, "新的书名")
        XCTAssertEqual(viewModel.continueReadingBook?.title, "新的书名")
    }

    func testDeletePersistsAndRefreshesShelf() async throws {
        let books = Self.books
        let repository = InMemoryBookRepository(books: books)
        let viewModel = LibraryViewModel(repository: repository)
        await viewModel.load()

        await viewModel.delete(books[0])

        let deletedBook = await repository.book(id: books[0].id)
        XCTAssertNil(deletedBook)
        XCTAssertEqual(viewModel.continueReadingBook?.id, books[1].id)
        XCTAssertEqual(viewModel.recentBooks.map(\.id), [books[2].id, books[3].id])
    }

    func testDeleteCompletesAfterNewerLoadAndReconcilesShelf() async {
        let books = Self.books
        let repository = DelayedSuccessfulMutationRepository(books: books)
        let viewModel = LibraryViewModel(repository: repository)

        let delete = Task { await viewModel.delete(books[0]) }
        await repository.waitUntilDeleteStarts()
        await viewModel.load()
        await repository.finishDelete()
        await delete.value

        let persistedBook = await repository.book(id: books[0].id)
        XCTAssertNil(persistedBook)
        XCTAssertNotEqual(viewModel.continueReadingBook?.id, books[0].id)
        XCTAssertFalse(viewModel.recentBooks.contains { $0.id == books[0].id })
    }

    func testShelfRefreshReceivesWebTransfersBeforeLoadingBooks() async {
        let book = Self.books[0]
        let repository = InMemoryBookRepository(books: [book])
        var receiveCount = 0
        let viewModel = LibraryViewModel(
            repository: repository,
            receiveWebTransfers: {
                receiveCount += 1
                return nil
            }
        )

        await viewModel.refreshAndReceiveWebTransfers()

        XCTAssertEqual(receiveCount, 1)
        XCTAssertEqual(viewModel.continueReadingBook?.id, book.id)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAccessibilityProgressUsesChineseSpellOut() {
        XCTAssertEqual(BookRow.accessibilityLabel(for: .fixture(position: nil)), "活着，余华，已读百分之零")
        XCTAssertEqual(
            BookRow.accessibilityLabel(for: .fixture(position: .init(href: "35", progression: 0.35))),
            "活着，余华，已读百分之三十五"
        )
        XCTAssertEqual(
            BookRow.accessibilityLabel(for: .fixture(position: .init(href: "100", progression: 1))),
            "活着，余华，已读百分之一百"
        )
    }

    func testStaleOpenFailureDoesNotOverwriteNewerLoad() async {
        let oldBook = Self.books[0]
        let newBook = Self.books[1]
        let repository = DelayedFailingSaveRepository(loadedBook: newBook)
        let viewModel = LibraryViewModel(repository: repository)

        let staleOpen = Task { await viewModel.open(oldBook) }
        await repository.waitUntilSaveStarts()
        await viewModel.load()
        await repository.finishSave()
        await staleOpen.value

        XCTAssertEqual(viewModel.continueReadingBook?.id, newBook.id)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLibraryNavigationBarAppearanceIsOpaque() {
        let appearance = LibraryNavigationBarStyle.makeAppearance()

        XCTAssertNil(appearance.backgroundEffect)
        XCTAssertEqual(appearance.backgroundColor, .systemGroupedBackground)
    }

    private static let books: [Book] = [
        .fixture(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "活着",
            author: "余华",
            position: .init(href: "c3", progression: 0.35),
            lastOpenedAt: Date(timeIntervalSince1970: 400),
            createdAt: Date(timeIntervalSince1970: 40)
        ),
        .fixture(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "许三观卖血记",
            author: "余华",
            position: .init(href: "c6", progression: 0.62),
            lastOpenedAt: Date(timeIntervalSince1970: 300),
            createdAt: Date(timeIntervalSince1970: 30)
        ),
        .fixture(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "围城",
            author: "钱钟书",
            position: .init(href: "c2", progression: 0.12),
            lastOpenedAt: Date(timeIntervalSince1970: 200),
            createdAt: Date(timeIntervalSince1970: 20)
        ),
        .fixture(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "平凡的世界",
            author: "路遥",
            position: .init(href: "end", progression: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 10)
        )
    ]
}

private actor DelayedSuccessfulMutationRepository: BookRepository {
    private var books: [Book]
    private var pendingSave: Book?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var saveStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private var pendingDeleteID: UUID?
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var deleteStartedContinuations: [CheckedContinuation<Void, Never>] = []

    init(books: [Book]) {
        self.books = books
    }

    func allBooks() -> [Book] { books }

    func recentBooks(limit: Int) -> [Book] {
        Array(books.prefix(limit))
    }

    func book(id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    func save(_ book: Book) async {
        pendingSave = book
        saveStartedContinuations.forEach { $0.resume() }
        saveStartedContinuations.removeAll()
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
        } else {
            books.append(book)
        }
        pendingSave = nil
    }

    func updatePosition(id: UUID, position: ReadingPosition?) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].position = position
    }

    func delete(id: UUID) async {
        pendingDeleteID = id
        deleteStartedContinuations.forEach { $0.resume() }
        deleteStartedContinuations.removeAll()
        await withCheckedContinuation { continuation in
            deleteContinuation = continuation
        }
        books.removeAll { $0.id == id }
        pendingDeleteID = nil
    }

    func waitUntilSaveStarts() async {
        guard pendingSave == nil else { return }
        await withCheckedContinuation { continuation in
            saveStartedContinuations.append(continuation)
        }
    }

    func finishSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func waitUntilDeleteStarts() async {
        guard pendingDeleteID == nil else { return }
        await withCheckedContinuation { continuation in
            deleteStartedContinuations.append(continuation)
        }
    }

    func finishDelete() {
        deleteContinuation?.resume()
        deleteContinuation = nil
    }
}

private actor DelayedFailingSaveRepository: BookRepository {
    private let loadedBook: Book
    private var saveStarted = false
    private var saveContinuation: CheckedContinuation<Void, Never>?

    init(loadedBook: Book) {
        self.loadedBook = loadedBook
    }

    func allBooks() -> [Book] { [loadedBook] }
    func recentBooks(limit: Int) -> [Book] { limit > 0 ? [loadedBook] : [] }
    func book(id: UUID) -> Book? { id == loadedBook.id ? loadedBook : nil }

    func save(_ book: Book) async throws {
        saveStarted = true
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
        throw SaveError.failed
    }

    func updatePosition(id: UUID, position: ReadingPosition?) {}

    func delete(id: UUID) {}

    func waitUntilSaveStarts() async {
        while !saveStarted {
            await Task.yield()
        }
    }

    func finishSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    private enum SaveError: Error {
        case failed
    }
}
