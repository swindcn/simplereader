import Foundation
@testable import PureVoice

extension Book {
    static func fixture(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        title: String = "活着",
        author: String = "余华",
        format: BookFormat = .epub,
        originalFileURL: URL? = nil,
        canonicalFileURL: URL? = nil,
        coverFileURL: URL? = nil,
        position: ReadingPosition? = nil,
        lastOpenedAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            format: format,
            originalFileURL: originalFileURL
                ?? URL(fileURLWithPath: "/tmp/\(id.uuidString)/original.epub"),
            canonicalFileURL: canonicalFileURL
                ?? URL(fileURLWithPath: "/tmp/\(id.uuidString)/publication.epub"),
            coverFileURL: coverFileURL,
            position: position,
            lastOpenedAt: lastOpenedAt,
            createdAt: createdAt
        )
    }
}
