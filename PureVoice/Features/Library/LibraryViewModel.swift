import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var continueReadingBook: Book?
    @Published private(set) var recentBooks: [Book] = []

    private let repository: any BookRepository
    private let now: () -> Date
    private let onOpenBook: (Book) -> Void
    private var requestGeneration = 0

    init(
        repository: any BookRepository,
        now: @escaping () -> Date = Date.init,
        onOpenBook: @escaping (Book) -> Void = { _ in }
    ) {
        self.repository = repository
        self.now = now
        self.onOpenBook = onOpenBook
    }

    func load() async {
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil

        do {
            let orderedBooks = try await repository.recentBooks(limit: .max)
            guard generation == requestGeneration else { return }
            apply(orderedBooks)
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = "无法加载书架：\(error.localizedDescription)"
        }

        guard generation == requestGeneration else { return }
        isLoading = false
    }

    func open(_ book: Book) async {
        requestGeneration += 1
        let generation = requestGeneration
        var updatedBook = book
        updatedBook.lastOpenedAt = now()

        do {
            try await repository.save(updatedBook)
            guard generation == requestGeneration else { return }
            onOpenBook(updatedBook)
            await load()
        } catch {
            guard generation == requestGeneration else { return }
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

        requestGeneration += 1
        let generation = requestGeneration
        var updatedBook = book
        updatedBook.title = trimmedTitle
        do {
            try await repository.save(updatedBook)
            guard generation == requestGeneration else { return }
            await load()
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = "无法重命名《\(book.title)》：\(error.localizedDescription)"
            isLoading = false
        }
    }

    func delete(_ book: Book) async {
        requestGeneration += 1
        let generation = requestGeneration
        do {
            try await repository.delete(id: book.id)
            guard generation == requestGeneration else { return }
            await load()
        } catch {
            guard generation == requestGeneration else { return }
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
        recentBooks = Array(orderedBooks.lazy.filter { $0.id != continueBook?.id }.prefix(3))
    }
}
