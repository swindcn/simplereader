import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var continueReadingBook: Book?
    @Published private(set) var recentBooks: [Book] = []
    @Published private(set) var shelfBooks: [Book] = []

    private let repository: any BookRepository
    private let now: () -> Date
    private let onOpenBook: (Book) -> Void
    private let receiveWebTransfers: (() async -> UserFacingError?)?
    private var loadGeneration = 0
    private var mutationGeneration = 0

    init(
        repository: any BookRepository,
        now: @escaping () -> Date = Date.init,
        receiveWebTransfers: (() async -> UserFacingError?)? = nil,
        onOpenBook: @escaping (Book) -> Void = { _ in }
    ) {
        self.repository = repository
        self.now = now
        self.receiveWebTransfers = receiveWebTransfers
        self.onOpenBook = onOpenBook
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        do {
            let orderedBooks = try await repository.recentBooks(limit: .max)
            guard generation == loadGeneration else { return }
            apply(orderedBooks)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = "无法加载书架：\(error.localizedDescription)"
        }

        guard generation == loadGeneration else { return }
        isLoading = false
    }

    func refreshAndReceiveWebTransfers() async {
        if let receiveWebTransfers {
            if let error = await receiveWebTransfers() {
                errorMessage = "\(error.message)\n\(error.recoveryAction)"
            }
        }
        await load()
    }

    func open(_ book: Book) async {
        mutationGeneration += 1
        let generation = mutationGeneration
        loadGeneration += 1
        let initialLoadGeneration = loadGeneration
        var updatedBook = (try? await repository.book(id: book.id)) ?? book
        updatedBook.lastOpenedAt = now()

        do {
            try await repository.save(updatedBook)
            guard generation == mutationGeneration else { return }
            loadGeneration += 1
            onOpenBook(updatedBook)
            await load()
        } catch {
            guard generation == mutationGeneration,
                  initialLoadGeneration == loadGeneration else { return }
            errorMessage = "无法打开《\(book.title)》：\(error.localizedDescription)"
            isLoading = false
        }
    }

    func rename(_ book: Book, to title: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "书名不能为空"
            return
        }

        mutationGeneration += 1
        let generation = mutationGeneration
        loadGeneration += 1
        let initialLoadGeneration = loadGeneration
        var updatedBook = book
        updatedBook.title = trimmedTitle
        do {
            try await repository.save(updatedBook)
            guard generation == mutationGeneration else { return }
            loadGeneration += 1
            await load()
        } catch {
            guard generation == mutationGeneration,
                  initialLoadGeneration == loadGeneration else { return }
            errorMessage = "无法重命名《\(book.title)》：\(error.localizedDescription)"
            isLoading = false
        }
    }

    func delete(_ book: Book) async {
        mutationGeneration += 1
        let generation = mutationGeneration
        loadGeneration += 1
        let initialLoadGeneration = loadGeneration
        do {
            try await repository.delete(id: book.id)
            guard generation == mutationGeneration else { return }
            loadGeneration += 1
            await load()
        } catch {
            guard generation == mutationGeneration,
                  initialLoadGeneration == loadGeneration else { return }
            errorMessage = "无法删除《\(book.title)》：\(error.localizedDescription)"
            isLoading = false
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func apply(_ orderedBooks: [Book]) {
        let continueBook = orderedBooks
            .filter { $0.lastOpenedAt != nil }
            .max { lhs, rhs in
                let lhsDate = lhs.lastOpenedAt ?? .distantPast
                let rhsDate = rhs.lastOpenedAt ?? .distantPast
                return lhsDate < rhsDate
            }
        continueReadingBook = continueBook
        shelfBooks = orderedBooks.filter { $0.id != continueBook?.id }
        recentBooks = Array(shelfBooks.prefix(3))
    }
}
