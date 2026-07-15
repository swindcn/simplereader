import CoreData
import Foundation

enum CoreDataBookRepositoryError: Error, Equatable, Sendable {
    case missingRequiredField(String)
    case unknownFormat(String)
    case invalidPositionData
}

final class CoreDataBookRepository: BookRepository, @unchecked Sendable {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func allBooks() async throws -> [Book] {
        try await fetchBooks().sorted(by: Self.libraryOrder)
    }

    func recentBooks(limit: Int) async throws -> [Book] {
        guard limit > 0 else { return [] }
        return Array(try await fetchBooks().sorted(by: Self.recentOrder).prefix(limit))
    }

    func book(id: UUID) async throws -> Book? {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
            request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
            request.fetchLimit = 1
            return try context.fetch(request).first.map(Self.mapBook)
        }
    }

    func save(_ book: Book) async throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
            request.predicate = NSPredicate(format: "id == %@", book.id as NSUUID)
            request.fetchLimit = 1
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: "BookEntity", into: context)

            object.setValue(book.id, forKey: "id")
            object.setValue(book.title, forKey: "title")
            object.setValue(book.author, forKey: "author")
            object.setValue(Self.string(for: book.format), forKey: "format")
            object.setValue(book.originalFileURL, forKey: "originalFileURL")
            object.setValue(book.canonicalFileURL, forKey: "canonicalFileURL")
            object.setValue(book.coverFileURL, forKey: "coverFileURL")
            object.setValue(try Self.encodePosition(book.position), forKey: "position")
            object.setValue(book.lastOpenedAt, forKey: "lastOpenedAt")
            object.setValue(book.createdAt, forKey: "createdAt")
            try context.save()
        }
    }

    func updatePosition(id: UUID, position: ReadingPosition?) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
            request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first else { return }
            object.setValue(try Self.encodePosition(position), forKey: "position")
            try context.save()
        }
    }

    func delete(id: UUID) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
            request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func fetchBooks() async throws -> [Book] {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
            return try context.fetch(request).map(Self.mapBook)
        }
    }

    private static func mapBook(_ object: NSManagedObject) throws -> Book {
        let id: UUID = try required("id", from: object)
        let title: String = try required("title", from: object)
        let author: String = try required("author", from: object)
        let formatString: String = try required("format", from: object)
        let originalFileURL: URL = try required("originalFileURL", from: object)
        let canonicalFileURL: URL = try required("canonicalFileURL", from: object)
        let createdAt: Date = try required("createdAt", from: object)

        return Book(
            id: id,
            title: title,
            author: author,
            format: try format(from: formatString),
            originalFileURL: originalFileURL,
            canonicalFileURL: canonicalFileURL,
            coverFileURL: object.value(forKey: "coverFileURL") as? URL,
            position: try decodePosition(object.value(forKey: "position") as? Data),
            lastOpenedAt: object.value(forKey: "lastOpenedAt") as? Date,
            createdAt: createdAt
        )
    }

    private static func required<Value>(_ key: String, from object: NSManagedObject) throws -> Value {
        guard let value = object.value(forKey: key) as? Value else {
            throw CoreDataBookRepositoryError.missingRequiredField(key)
        }
        return value
    }

    private static func string(for format: BookFormat) -> String {
        switch format {
        case .txt: "txt"
        case .epub: "epub"
        case .mobi: "mobi"
        }
    }

    private static func format(from value: String) throws -> BookFormat {
        switch value {
        case "txt": .txt
        case "epub": .epub
        case "mobi": .mobi
        default: throw CoreDataBookRepositoryError.unknownFormat(value)
        }
    }

    private struct PositionDTO: Codable {
        let href: String
        let locationsJSON: String?
        let progression: Double
    }

    private static func encodePosition(_ position: ReadingPosition?) throws -> Data? {
        guard let position else { return nil }
        return try JSONEncoder().encode(PositionDTO(
            href: position.href,
            locationsJSON: position.locationsJSON,
            progression: position.progression
        ))
    }

    private static func decodePosition(_ data: Data?) throws -> ReadingPosition? {
        guard let data else { return nil }
        do {
            let dto = try JSONDecoder().decode(PositionDTO.self, from: data)
            return ReadingPosition(
                href: dto.href,
                locationsJSON: dto.locationsJSON,
                progression: dto.progression
            )
        } catch {
            throw CoreDataBookRepositoryError.invalidPositionData
        }
    }

    private static func libraryOrder(_ lhs: Book, _ rhs: Book) -> Bool {
        let lhsDate = orderingKey(for: lhs.createdAt)
        let rhsDate = orderingKey(for: rhs.createdAt)
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func recentOrder(_ lhs: Book, _ rhs: Book) -> Bool {
        let lhsDate = orderingKey(for: lhs.lastOpenedAt ?? lhs.createdAt)
        let rhsDate = orderingKey(for: rhs.lastOpenedAt ?? rhs.createdAt)
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return libraryOrder(lhs, rhs)
    }

    private static func orderingKey(for date: Date) -> Double {
        let interval = date.timeIntervalSinceReferenceDate
        return interval.isFinite ? interval : -Double.greatestFiniteMagnitude
    }
}
