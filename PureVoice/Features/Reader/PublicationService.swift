import Foundation
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

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

struct ContinuousReaderChapterReference: Equatable, Identifiable, Sendable {
    let index: Int
    let title: String
    let href: String

    var id: String { href }
}

struct ContinuousReaderChapter: Equatable, Identifiable, Sendable {
    let index: Int
    let title: String
    let href: String
    let paragraphs: [String]

    var id: String { href }
}

@MainActor
final class OpenedPublication {
    let title: String
    let author: String?
    let coverURL: URL?
    let tableOfContents: [PublicationTOCItem]
    let readiumPublication: Publication

    init(
        publication: Publication,
        title: String,
        author: String?,
        coverURL: URL?,
        tableOfContents: [PublicationTOCItem]
    ) {
        readiumPublication = publication
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.tableOfContents = tableOfContents
    }

    func readingPosition(from locator: Locator) throws -> ReadingPosition {
        let locator = readiumPublication.normalizeLocator(locator)
        guard readiumPublication.linkWithHREF(locator.href) != nil else {
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
            progression: locator.locations.totalProgression ?? 0
        )
    }

    func locator(from position: ReadingPosition) async throws -> Locator {
        guard let json = position.locationsJSON else {
            guard let locator = await readiumPublication.locate(progression: position.progression) else {
                throw PublicationServiceError.invalidReadingPosition
            }
            return locator
        }

        do {
            guard let href = AnyURL(string: position.href) else {
                throw PublicationServiceError.invalidReadingPosition
            }
            let data = Data(json.utf8)
            let object = try JSONSerialization.jsonObject(with: data)
            var locations = try Locator.Locations(json: object)
            if locations.totalProgression == nil {
                locations.totalProgression = position.progression
            }
            let normalized = readiumPublication.normalizeLocator(
                Locator(href: href, mediaType: .xhtml, locations: locations)
            )
            guard let mediaType = readiumPublication.linkWithHREF(normalized.href)?.mediaType else {
                throw PublicationServiceError.invalidReadingPosition
            }
            return normalized.copy(mediaType: mediaType)
        } catch let error as PublicationServiceError {
            throw error
        } catch {
            throw PublicationServiceError.invalidReadingPosition
        }
    }

    func continuousChapterReferences() -> [ContinuousReaderChapterReference] {
        readiumPublication.readingOrder.enumerated().map { index, link in
            ContinuousReaderChapterReference(
                index: index,
                title: chapterTitle(for: link.href) ?? link.title?.trimmedNonEmpty ?? "第 \(index + 1) 章",
                href: link.href
            )
        }
    }

    func continuousChapter(for reference: ContinuousReaderChapterReference) async throws -> ContinuousReaderChapter {
        guard let href = AnyURL(string: reference.href),
              let link = readiumPublication.linkWithHREF(href),
              let resource = readiumPublication.get(link)
        else {
            throw PublicationServiceError.invalidPublication
        }

        let data: Data
        do {
            data = try await resource.read().get()
        } catch {
            throw PublicationServiceError.invalidPublication
        }

        let extracted = XHTMLBodyTextExtractor.extract(from: data)
        let title = extracted.title?.trimmedNonEmpty ?? reference.title
        let paragraphs = extracted.paragraphs.filter { $0.trimmedNonEmpty != nil }
        return ContinuousReaderChapter(
            index: reference.index,
            title: title,
            href: reference.href,
            paragraphs: paragraphs
        )
    }

    private func chapterTitle(for href: String) -> String? {
        let resource = href.resourceHREF
        return tableOfContents.flattened().first { item in
            item.href.resourceHREF == resource && !item.href.contains("#")
        }?.title ?? tableOfContents.flattened().first { item in
            item.href.resourceHREF == resource
        }?.title
    }
}

@MainActor
final class PublicationService: PublicationOpening {
    private let container: any ReadiumPublicationOpening

    init(container: any ReadiumPublicationOpening = ReadiumContainer()) {
        self.container = container
    }

    func open(at fileURL: URL) async throws -> OpenedPublication {
        let publication: Publication
        do {
            publication = try await container.openPublication(at: fileURL)
        } catch let error as PublicationServiceError {
            throw error
        } catch {
            throw mapOpenError(error)
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

        return OpenedPublication(
            publication: publication,
            title: title,
            author: author,
            coverURL: existingCoverURL(beside: fileURL),
            tableOfContents: tocLinks.map(PublicationTOCItem.init(link:))
        )
    }

    func openPublication(at canonicalURL: URL) async throws -> PublicationMetadata {
        let opened = try await open(at: canonicalURL)
        let coverURL: URL?
        do {
            coverURL = try await persistCover(of: opened.readiumPublication, beside: canonicalURL)
        } catch {
            throw PublicationServiceError.coverPersistenceFailed
        }
        return PublicationMetadata(title: opened.title, author: opened.author, coverURL: coverURL)
    }

    private func existingCoverURL(beside fileURL: URL) -> URL? {
        let coverURL = fileURL.deletingLastPathComponent().appendingPathComponent("cover")
        return FileManager.default.fileExists(atPath: coverURL.path) ? coverURL : nil
    }

    private func persistCover(of publication: Publication, beside fileURL: URL) async throws -> URL? {
        guard let image = try await publication.cover().get() else { return nil }
        guard let data = image.pngData() else {
            throw PublicationServiceError.coverPersistenceFailed
        }
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent("cover")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func mapOpenError(_ error: Error) -> PublicationServiceError {
        if error is ContentProtectionSchemeNotSupportedError {
            return .protectedPublication
        }
        if let error = error as? AssetRetrieveURLError {
            switch error {
            case .schemeNotSupported:
                return .invalidFileURL
            case .formatNotSupported:
                return .invalidPublication
            case let .reading(error):
                return mapReadError(error)
            }
        }
        if let error = error as? PublicationOpenError {
            switch error {
            case .formatNotSupported:
                return .invalidPublication
            case let .reading(error):
                return mapReadError(error)
            }
        }
        if let error = error as? ContentProtectionOpenError {
            switch error {
            case let .assetNotSupported(underlying):
                return underlying is ContentProtectionSchemeNotSupportedError
                    ? .protectedPublication
                    : .invalidPublication
            case let .reading(error):
                return mapReadError(error)
            }
        }
        return .invalidPublication
    }

    private func mapReadError(_ error: ReadError) -> PublicationServiceError {
        switch error {
        case .access:
            return .invalidFileURL
        case let .decoding(underlying):
            return underlying is ContentProtectionSchemeNotSupportedError
                ? .protectedPublication
                : .invalidPublication
        case .unsupportedOperation:
            return .invalidPublication
        }
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

private extension Array where Element == PublicationTOCItem {
    func flattened() -> [PublicationTOCItem] {
        flatMap { item in
            [item] + item.children.flattened()
        }
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var resourceHREF: String {
        split(separator: "#", maxSplits: 1).first.map(String.init) ?? self
    }
}

private struct XHTMLBodyTextExtractor {
    let title: String?
    let paragraphs: [String]

    static func extract(from data: Data) -> XHTMLBodyTextExtractor {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        return XHTMLBodyTextExtractor(
            title: delegate.heading.trimmedNonEmpty ?? delegate.documentTitle.trimmedNonEmpty,
            paragraphs: delegate.paragraphs
        )
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var documentTitle = ""
        var heading = ""
        var paragraphs: [String] = []

        private var isInBody = false
        private var captureTitle = false
        private var captureHeading = false
        private var captureParagraph = false
        private var buffer = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName.lowercased() {
            case "body":
                isInBody = true
            case "title":
                captureTitle = true
                buffer = ""
            case "h1", "h2":
                guard isInBody else { return }
                captureHeading = true
                buffer = ""
            case "p", "li", "blockquote":
                guard isInBody else { return }
                captureParagraph = true
                buffer = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard captureTitle || captureHeading || captureParagraph else { return }
            buffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch elementName.lowercased() {
            case "body":
                isInBody = false
            case "title":
                if captureTitle {
                    documentTitle = normalized(buffer)
                    captureTitle = false
                    buffer = ""
                }
            case "h1", "h2":
                if captureHeading {
                    if heading.isEmpty {
                        heading = normalized(buffer)
                    }
                    captureHeading = false
                    buffer = ""
                }
            case "p", "li", "blockquote":
                if captureParagraph {
                    if let paragraph = normalized(buffer).trimmedNonEmpty {
                        paragraphs.append(paragraph)
                    }
                    captureParagraph = false
                    buffer = ""
                }
            default:
                break
            }
        }

        private func normalized(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
