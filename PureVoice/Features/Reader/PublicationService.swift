import Foundation
@preconcurrency import ReadiumShared

enum PublicationServiceError: Error, Equatable, LocalizedError {
    case invalidFileURL
    case invalidPublication
    case protectedPublication
    case coverPersistenceFailed
    case invalidReadingPosition

    var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "无法访问所选 EPUB 文件。"
        case .invalidPublication:
            return "无法打开此 EPUB，文件可能已损坏或格式不受支持。"
        case .protectedPublication:
            return "此 EPUB 受 DRM 保护，暂不支持打开。"
        case .coverPersistenceFailed:
            return "无法保存 EPUB 封面。"
        case .invalidReadingPosition:
            return "无法恢复上次阅读位置。"
        }
    }
}

struct PublicationTOCItem: Equatable, Sendable {
    let title: String
    let href: String
    let children: [PublicationTOCItem]

    init(title: String, href: String, children: [PublicationTOCItem] = []) {
        self.title = title
        self.href = href
        self.children = children
    }
}

@MainActor
final class OpenedPublication {
    let title: String
    let author: String?
    let coverURL: URL?
    let tableOfContents: [PublicationTOCItem]

    private let publication: Publication

    init(
        publication: Publication,
        title: String,
        author: String?,
        coverURL: URL?,
        tableOfContents: [PublicationTOCItem]
    ) {
        self.publication = publication
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.tableOfContents = tableOfContents
    }

    func readingPosition(from locator: Locator) throws -> ReadingPosition {
        let locator = publication.normalizeLocator(locator)
        guard publication.linkWithHREF(locator.href) != nil else {
            throw PublicationServiceError.invalidReadingPosition
        }
        let locationsData = try JSONSerialization.data(
            withJSONObject: locator.locations.json,
            options: [.sortedKeys]
        )
        let locationsJSON = String(data: locationsData, encoding: .utf8)
        return ReadingPosition(
            href: locator.href.string,
            locationsJSON: locationsJSON,
            progression: locator.locations.totalProgression ?? locator.locations.progression ?? 0
        )
    }

    func locator(from position: ReadingPosition) throws -> Locator {
        guard let href = AnyURL(string: position.href),
              let link = publication.linkWithHREF(href),
              let mediaType = link.mediaType
        else {
            throw PublicationServiceError.invalidReadingPosition
        }

        let locations: Locator.Locations
        if let json = position.locationsJSON {
            do {
                let data = Data(json.utf8)
                let object = try JSONSerialization.jsonObject(with: data)
                locations = try Locator.Locations(json: object)
            } catch {
                throw PublicationServiceError.invalidReadingPosition
            }
        } else {
            locations = Locator.Locations(progression: position.progression)
        }
        return publication.normalizeLocator(Locator(href: href, mediaType: mediaType, locations: locations))
    }
}

@MainActor
final class PublicationService: PublicationOpening {
    private let container: ReadiumContainer

    init(container: ReadiumContainer = ReadiumContainer()) {
        self.container = container
    }

    func open(at fileURL: URL) async throws -> OpenedPublication {
        let publication: Publication
        do {
            publication = try await container.openPublication(at: fileURL)
        } catch let error as PublicationServiceError {
            throw error
        } catch {
            throw PublicationServiceError.invalidPublication
        }

        guard publication.conforms(to: .epub) else {
            throw PublicationServiceError.invalidPublication
        }
        guard !publication.isProtected, !publication.isRestricted else {
            throw PublicationServiceError.protectedPublication
        }

        let title = normalized(publication.metadata.title)
            ?? fileURL.deletingPathExtension().lastPathComponent
        let authors = publication.metadata.authors.compactMap { normalized($0.name) }
        let author = authors.isEmpty ? nil : authors.joined(separator: ", ")

        let tocLinks: [Link]
        do {
            tocLinks = try await publication.tableOfContents().get()
        } catch {
            throw PublicationServiceError.invalidPublication
        }

        let coverURL: URL?
        do {
            coverURL = try await persistCover(of: publication, beside: fileURL)
        } catch {
            throw PublicationServiceError.coverPersistenceFailed
        }

        return OpenedPublication(
            publication: publication,
            title: title,
            author: author,
            coverURL: coverURL,
            tableOfContents: tocLinks.map(PublicationTOCItem.init(link:))
        )
    }

    func openPublication(at canonicalURL: URL) async throws -> PublicationMetadata {
        let opened = try await open(at: canonicalURL)
        return PublicationMetadata(title: opened.title, author: opened.author, coverURL: opened.coverURL)
    }

    private func persistCover(of publication: Publication, beside fileURL: URL) async throws -> URL? {
        guard let image = try await publication.cover().get() else { return nil }
        guard let data = image.pngData() else {
            throw PublicationServiceError.coverPersistenceFailed
        }
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent("cover.png")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private extension PublicationTOCItem {
    init(link: Link) {
        let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: title.flatMap { $0.isEmpty ? nil : $0 } ?? link.href,
            href: link.href,
            children: link.children.map(PublicationTOCItem.init(link:))
        )
    }
}
