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
            let entryData = try await data(for: entry, in: archive)
            let parser = XMLParser(data: entryData)
            XCTAssertTrue(parser.parse(), "Invalid XML in \(entry.path): \(String(describing: parser.parserError))")
        }
        let opf = String(decoding: try await data(for: entries[2], in: archive), as: UTF8.self)
        let nav = String(decoding: try await data(for: entries[3], in: archive), as: UTF8.self)
        let xhtml = String(decoding: try await data(for: entries[4], in: archive), as: UTF8.self)
        XCTAssertTrue(opf.contains("书 &amp; &lt;名&gt; &quot;x&quot;"))
        XCTAssertTrue(nav.contains("第一章 &amp; &lt;开场&gt;"))
        XCTAssertTrue(xhtml.contains("A &amp; B &lt; C &gt; D &quot;quote&quot; &apos;apostrophe&apos;"))
        XCTAssertTrue(xhtml.contains("第二节&#xFFFD;"))
        let collector = XMLTextCollector()
        let decodedParser = XMLParser(data: try await data(for: entries[4], in: archive))
        decodedParser.delegate = collector
        XCTAssertTrue(decodedParser.parse())
        XCTAssertTrue(collector.text.contains("第一章 & <开场>"))
        XCTAssertTrue(collector.text.contains("A & B < C > D \"quote\" 'apostrophe'"))
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

    func testAdapterUsesSuggestedSourceTitleAndRejectsOtherFormats() async throws {
        let source = fixtureURL("utf8-novel.txt")
        let destination = temporaryURL("adapter.epub")
        try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .txt, suggestedTitle: "原始书名", destinationURL: destination)
        let publication = try await openPublication(at: destination)
        XCTAssertEqual(publication.metadata.title, "原始书名")
        do {
            try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .epub, suggestedTitle: "Title", destinationURL: temporaryURL("bad.epub"))
            XCTFail("Expected unsupported format")
        } catch {
            XCTAssertEqual(error as? TXTConversionError, .unsupportedFormat(.epub))
        }
    }

    func testAdapterTrustsDetectedTXTRegardlessOfStoredExtension() async throws {
        let source = temporaryURL("disguised.epub")
        try fixtureData("utf8-novel.txt").write(to: source)
        let destination = temporaryURL("accepted.epub")
        try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .txt, suggestedTitle: "Detected", destinationURL: destination)
        let publication = try await openPublication(at: destination)
        XCTAssertEqual(publication.metadata.title, "Detected")
    }

    func testSameInputBuildsByteIdenticalEPUBs() async throws {
        let chapters = [Chapter(index: 0, title: "第一章", body: "内容"), Chapter(index: 1, title: "Chapter 2", body: "Body")]
        let first = temporaryURL("first.epub")
        let second = temporaryURL("second.epub")
        try await EPUBBuilder().build(chapters: chapters, title: "Stable", author: "Author", destinationURL: first)
        try await EPUBBuilder().build(chapters: chapters, title: "Stable", author: "Author", destinationURL: second)
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
    }

    func testTXTSourceLimitCoversTwentyMiBPerformanceBaseline() {
        XCTAssertGreaterThanOrEqual(TXTCanonicalPublicationConverter.maximumSourceBytes, 20 * 1_024 * 1_024)
    }

    func testTwentyMiBSparseSourceIsNotRejectedAsTooLarge() async throws {
        let source = temporaryURL("performance-baseline.txt")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(20 * 1_024 * 1_024))
        try handle.close()

        do {
            try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .txt, suggestedTitle: "Baseline", destinationURL: temporaryURL("baseline.epub"))
            XCTFail("The sparse fixture should fail encoding detection")
        } catch let error as TXTDecodingError {
            XCTAssertEqual(error, .unsupportedEncoding)
        } catch TXTConversionError.fileTooLarge {
            XCTFail("The 20 MiB performance fixture must pass the TXT size gate")
        } catch {
            XCTFail("Unexpected conversion error: \(error)")
        }
    }

    func testAdapterRejectsSparseSourceAboveThirtyTwoMiBLimitWithoutReadingIt() async throws {
        let source = temporaryURL("large.txt")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(32 * 1_024 * 1_024 + 1))
        try handle.close()
        let startedAt = Date()
        do {
            try await TXTCanonicalPublicationConverter().convert(originalURL: source, format: .txt, suggestedTitle: "Large", destinationURL: temporaryURL("large.epub"))
            XCTFail("Expected size rejection")
        } catch {
            XCTAssertEqual(error as? TXTConversionError, .fileTooLarge(maxBytes: 32 * 1_024 * 1_024))
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
        }
    }

    func testTXTSizeErrorDescribesThirtyTwoMBLimit() {
        let error = TXTConversionError.fileTooLarge(maxBytes: 32 * 1_024 * 1_024)
        XCTAssertEqual(error.errorDescription, "TXT 文件超过 32 MB 本地转换上限。")
    }

    func testCancelledBuildKeepsExistingDestination() async throws {
        let destination = temporaryURL("existing.epub")
        let old = Data("old canonical".utf8)
        try old.write(to: destination)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await EPUBBuilder().build(chapters: [Chapter(index: 0, title: "One", body: "Body")], title: "Cancelled", destinationURL: destination)
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: destination), old)
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
        try! Data(contentsOf: fixtureURL(name))
    }

    private func fixtureURL(_ name: String) -> URL {
        Bundle(for: Self.self).url(forResource: name, withExtension: nil)!
    }

    private func openPublication(at url: URL) async throws -> Publication {
        let httpClient: HTTPClient = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: httpClient, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()), contentProtections: [])
        return try await opener.open(asset: try await retriever.retrieve(url: FileURL(url: url)!).get(), allowUserInteraction: false, sender: nil).get()
    }
}

private final class XMLTextCollector: NSObject, XMLParserDelegate {
    private(set) var text = ""
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
}

private actor DataCollector {
    private(set) var value = Data()

    func append(_ data: Data) {
        value.append(data)
    }
}
