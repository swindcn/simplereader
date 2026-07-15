import Foundation

protocol BookRepository: Sendable {
    func allBooks() async throws -> [Book]
    func recentBooks(limit: Int) async throws -> [Book]
    func book(id: UUID) async throws -> Book?
    func save(_ book: Book) async throws
    func updatePosition(id: UUID, position: ReadingPosition?) async throws
    func delete(id: UUID) async throws
}
