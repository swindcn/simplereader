import Foundation
import ReadiumShared
import ReadiumStreamer
import ReadiumZIPFoundation
import XCTest
@testable import PureVoice

final class EPUBBuilderTests: XCTestCase {
    func testBuildsCanonicalEPUBWithValidXMLAndRequiredZIPOrder() async throws {
        let chapters = [
            Chapter(index: 0, title: "第一章 & <开场>", body: "A & B < C > D \"quote\" 'apostrophe'\n\n第二节\u{1}"),
            Chapter(index: 1, title: "Chapter 2", body: "Body")
        ]
        let url = temporaryURL("special.epub")
        try await EPUBBuilder().build(chapters: chapters, title: "书 & <名> \"x\"", author: "作者 & A", language: "zh-CN", destinationURL: url)

        let archive = try await Archive(url: url, accessMode: .read)
        let entries = try await archive.entries()
        XCTAssertEqual(entries.first?.path, "mimetype")
        XCTAssertEqual(entries.first?.isCompressed, false)
        let mimetype = try await data(for: entries[0], in: archive)
        XCTAssertEqual(mimetype, Data("application/epub+zip".utf8))
        XCTAssertEqual(entries.map(\.path), ["mimetype", "META-INF/container.xml", "EPUB/package.opf", "EPUB/nav.xhtml", "EPUB/chapter-0001.xhtml", "EPUB/chapter-0002.xhtml"])
        for entry in entries where entry.path.hasSuffix(".xml") || entry.path.hasSuffix(".opf") || entry.path.hasSuffix(".xhtml") {
            let parser = XMLParser(data: try await data(for: entry, in: archive))
            XCTAssertTrue(parser.parse(), "Invalid XML in \(entry.path): \(String(describing: parser.parserError))")
        }
    }

    func testReadiumOpensBuiltEPUBAndSeesMetadataSpineAndTOC() async throws {
        let chapters = ChapterParser().parse(String(data: fixtureData("utf8-novel.txt"), encoding: .utf8)!)
        let url = temporaryURL("readium.epub")
        try await EPUBBuilder().build(chapters: chapters, title: "  测试小说  ", author: nil, destinationURL: url)

        let httpClient: HTTPClient = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: httpClient, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()), contentProtections: [])
        let asset = try await retriever.retrieve(url: FileURL(url: url)!).get()
        let publication = try await opener.open(asset: asset, allowUserInteraction: false, sender: nil).get()
        XCTAssertEqual(publication.metadata.title, "测试小说")
        XCTAssertEqual(publication.readingOrder.count, chapters.count)
        let tableOfContents = try await publication.tableOfContents().get()
        XCTAssertEqual(tableOfContents.count, chapters.count)
    }

    func testBuilderProvidesFallbackChapterAndMetadataForEmptyInputs() async throws {
        let url = temporaryURL("fallback.epub")
        try await EPUBBuilder().build(chapters: [], title: "  ", author: "\n", language: "", destinationURL: url)
        let httpClient: HTTPClient = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: httpClient, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()), contentProtections: [])
        let asset = try await retriever.retrieve(url: FileURL(url: url)!).get()
        let publication = try await opener.open(asset: asset, allowUserInteraction: false, sender: nil).get()
        XCTAssertEqual(publication.metadata.title, "未命名作品")
        XCTAssertEqual(publication.readingOrder.count, 1)
        let tableOfContents = try await publication.tableOfContents().get()
        XCTAssertEqual(tableOfContents.first?.title, "正文")
    }

    func testAdapterConvertsTXTAndRejectsOtherFormats() async throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/txt/utf8-novel.txt")
        let destination = temporaryURL("adapter.epub")
        try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .txt, destinationURL: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        do {
            try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .epub, destinationURL: temporaryURL("bad.epub"))
            XCTFail("Expected unsupported format")
        } catch {
            XCTAssertEqual(error as? TXTConversionError, .unsupportedFormat(.epub))
        }
    }

    func testAdapterRejectsNonTXTExtensionEvenWhenFormatWasMisreported() async throws {
        let source = temporaryURL("disguised.epub")
        try fixtureData("utf8-novel.txt").write(to: source)
        do {
            try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .txt, destinationURL: temporaryURL("bad.epub"))
            XCTFail("Expected unsupported extension")
        } catch {
            XCTAssertEqual(error as? TXTConversionError, .unsupportedFileExtension("epub"))
        }
    }

    private func data(for entry: Entry, in archive: Archive) async throws -> Data {
        let collector = DataCollector()
        _ = try await archive.extract(entry) { chunk in await collector.append(chunk) }
        return await collector.value
    }

    private func temporaryURL(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(name)
    }

    private func fixtureData(_ name: String) -> Data {
        try! Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/txt/\(name)"))
    }
}

private actor DataCollector {
    private(set) var value = Data()

    func append(_ data: Data) {
        value.append(data)
    }
}
