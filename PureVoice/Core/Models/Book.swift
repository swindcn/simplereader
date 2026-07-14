import Foundation

struct Book: Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var format: BookFormat
    var originalFileURL: URL
    var canonicalFileURL: URL
    var coverFileURL: URL?
    var position: ReadingPosition?
    var lastOpenedAt: Date?
    var createdAt: Date
}
