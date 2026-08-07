import Foundation

final class PathRelocatingBookRepository: BookRepository, @unchecked Sendable {
    private let base: any BookRepository
    private let fileStore: BookFileStore

    init(base: any BookRepository, fileStore: BookFileStore) {
        self.base = base
        self.fileStore = fileStore
    }

    func allBooks() async throws -> [Book] {
        try await base.allBooks().map(relocated)
    }

    func recentBooks(limit: Int) async throws -> [Book] {
        try await base.recentBooks(limit: limit).map(relocated)
    }

    func book(id: UUID) async throws -> Book? {
        try await base.book(id: id).map(relocated)
    }

    func save(_ book: Book) async throws {
        try await base.save(book)
    }

    func updatePosition(id: UUID, position: ReadingPosition?) async throws {
        try await base.updatePosition(id: id, position: position)
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }

    private func relocated(_ book: Book) -> Book {
        var book = book
        book.originalFileURL = fileStore.originalURL(for: book.id, format: book.format)
        book.canonicalFileURL = fileStore.canonicalURL(for: book.id)
        if book.coverFileURL != nil {
            book.coverFileURL = fileStore.coverURL(for: book.id)
        }
        return book
    }
}
