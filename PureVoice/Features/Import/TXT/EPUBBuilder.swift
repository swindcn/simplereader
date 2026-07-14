import Foundation
import CryptoKit
import ReadiumZIPFoundation

enum EPUBBuilderError: Error, LocalizedError {
    case unableToEncodeEntry(String)

    var errorDescription: String? {
        switch self {
        case let .unableToEncodeEntry(path): return "无法生成 EPUB 文件：\(path)"
        }
    }
}

struct EPUBBuilder: Sendable {
    private let xml = XMLTextEncoder()
    private static let archiveDate = Date(timeIntervalSince1970: 946_684_800)

    func build(
        chapters: [Chapter],
        title: String,
        author: String? = nil,
        language: String = "zh-CN",
        destinationURL: URL
    ) async throws {
        try Task.checkCancellation()
        let normalizedChapters = chapters.isEmpty
            ? [Chapter(index: 0, title: "正文", body: "")]
            : chapters
        let normalizedTitle = fallback(title, value: "未命名作品")
        let normalizedAuthor = fallback(author ?? "", value: "未知作者")
        let normalizedLanguage = fallback(language, value: "zh-CN")
        let publicationIdentifier = stableIdentifier(
            chapters: normalizedChapters,
            title: normalizedTitle,
            author: normalizedAuthor,
            language: normalizedLanguage
        )
        let fileManager = FileManager.default
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporaryURL = parent.appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let archive = try await Archive(url: temporaryURL, accessMode: .create)
        try await add(Data("application/epub+zip".utf8), path: "mimetype", compression: .none, to: archive)
        try await addXML(containerDocument, path: "META-INF/container.xml", to: archive)
        try await addXML(packageDocument(chapters: normalizedChapters, title: normalizedTitle, author: normalizedAuthor, language: normalizedLanguage, identifier: publicationIdentifier), path: "EPUB/package.opf", to: archive)
        try await addXML(navigationDocument(chapters: normalizedChapters, title: normalizedTitle, language: normalizedLanguage), path: "EPUB/nav.xhtml", to: archive)
        for (offset, chapter) in normalizedChapters.enumerated() {
            try Task.checkCancellation()
            try await addXML(chapterDocument(chapter, language: normalizedLanguage), path: chapterPath(offset), to: archive)
        }
        try Task.checkCancellation()

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private var containerDocument: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
    }

    private func packageDocument(chapters: [Chapter], title: String, author: String, language: String, identifier: String) -> String {
        let manifest = chapters.indices.map { "<item id=\"chapter-\($0 + 1)\" href=\"\(chapterFilename($0))\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let spine = chapters.indices.map { "<itemref idref=\"chapter-\($0 + 1)\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="\(xml.encode(language))"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="pub-id">urn:sha256:\(identifier)</dc:identifier><dc:title>\(xml.encode(title))</dc:title><dc:creator>\(xml.encode(author))</dc:creator><dc:language>\(xml.encode(language))</dc:language><meta property="dcterms:modified">2000-01-01T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\(manifest)</manifest><spine>\(spine)</spine></package>
        """
    }

    private func navigationDocument(chapters: [Chapter], title: String, language: String) -> String {
        let items = chapters.enumerated().map { offset, chapter in
            "<li><a href=\"\(chapterFilename(offset))\">\(xml.encode(fallback(chapter.title, value: "第 \(offset + 1) 章")))</a></li>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(xml.encode(language))"><head><meta charset="UTF-8"/><title>\(xml.encode(title))</title></head><body><nav epub:type="toc" id="toc"><h1>目录</h1><ol>\(items)</ol></nav></body></html>
        """
    }

    private func chapterDocument(_ chapter: Chapter, language: String) -> String {
        let title = fallback(chapter.title, value: "正文")
        let content = chapter.body.components(separatedBy: "\n").map { line in
            line.isEmpty ? "<div class=\"section-break\" aria-hidden=\"true\"></div>" : "<p>\(xml.encode(line))</p>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(xml.encode(language))"><head><meta charset="UTF-8"/><title>\(xml.encode(title))</title><style>body{line-height:1.7;margin:5%;}p{margin:0 0 1em;}.section-break{height:1em;}</style></head><body><h1>\(xml.encode(title))</h1>\(content)</body></html>
        """
    }

    private func addXML(_ string: String, path: String, to archive: Archive) async throws {
        try Task.checkCancellation()
        guard let data = string.data(using: .utf8) else { throw EPUBBuilderError.unableToEncodeEntry(path) }
        try await add(data, path: path, compression: .deflate, to: archive)
    }

    private func add(_ data: Data, path: String, compression: CompressionMethod, to archive: Archive) async throws {
        try Task.checkCancellation()
        try await archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), modificationDate: Self.archiveDate, compressionMethod: compression) { position, size in
            try Task.checkCancellation()
            let start = Int(position)
            guard start < data.count else { return Data() }
            return data.subdata(in: start..<min(start + size, data.count))
        }
    }

    private func chapterPath(_ index: Int) -> String { "EPUB/\(chapterFilename(index))" }
    private func chapterFilename(_ index: Int) -> String { String(format: "chapter-%04d.xhtml", index + 1) }

    private func fallback(_ value: String, value fallbackValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackValue : trimmed
    }

    private func stableIdentifier(chapters: [Chapter], title: String, author: String, language: String) -> String {
        var hasher = SHA256()
        func update(_ value: String) {
            let data = Data(value.utf8)
            var length = UInt64(data.count).littleEndian
            withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
            hasher.update(data: data)
        }
        update(title)
        update(author)
        update(language)
        for (index, chapter) in chapters.enumerated() {
            update(fallback(chapter.title, value: "第 \(index + 1) 章"))
            update(chapter.body)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
