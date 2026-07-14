import Foundation

actor InMemoryBookRepository: BookRepository {
    private var booksByID: [UUID: Book] = [:]

    func allBooks() -> [Book] {
        booksByID.values.sorted(by: Self.libraryOrder)
    }

    func recentBooks(limit: Int) -> [Book] {
        guard limit > 0 else { return [] }
        return Array(booksByID.values.sorted(by: Self.recentOrder).prefix(limit))
    }

    func book(id: UUID) -> Book? {
        booksByID[id]
    }

    func save(_ book: Book) {
        booksByID[book.id] = book
    }

    func delete(id: UUID) {
        booksByID[id] = nil
    }

    private static func libraryOrder(_ lhs: Book, _ rhs: Book) -> Bool {
        let lhsDate = orderingKey(for: lhs.createdAt)
        let rhsDate = orderingKey(for: rhs.createdAt)
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func recentOrder(_ lhs: Book, _ rhs: Book) -> Bool {
        let lhsDate = orderingKey(for: lhs.lastOpenedAt ?? lhs.createdAt)
        let rhsDate = orderingKey(for: rhs.lastOpenedAt ?? rhs.createdAt)
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return libraryOrder(lhs, rhs)
    }

    private static func orderingKey(for date: Date) -> Double {
        let interval = date.timeIntervalSinceReferenceDate
        return interval.isFinite ? interval : -Double.greatestFiniteMagnitude
    }
}
