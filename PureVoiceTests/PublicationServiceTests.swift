import enum ReadiumShared.AnyURL
import enum ReadiumShared.AssetRetrieveURLError
import struct ReadiumShared.ContentProtectionSchemeNotSupportedError
import struct ReadiumShared.Locator
import struct ReadiumShared.MediaType
import class ReadiumShared.Publication
import enum ReadiumStreamer.PublicationOpenError
import XCTest
@testable import PureVoice

@MainActor
final class PublicationServiceTests: XCTestCase {
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicationServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testOpensEPUBAndNormalizesMetadataAndStableCover() async throws {
        let epubURL = try copyFixture("minimal.epub")
        let service = PublicationService()

        let metadata = try await service.openPublication(at: epubURL)

        XCTAssertEqual(metadata.title, "无障碍阅读示例")
        XCTAssertEqual(metadata.author, "示例作者")
        let coverURL = try XCTUnwrap(metadata.coverURL)
        XCTAssertEqual(coverURL, epubURL.deletingLastPathComponent().appendingPathComponent("cover"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverURL.path))
        XCTAssertFalse(try Data(contentsOf: coverURL).isEmpty)

        let opened = try await service.open(at: epubURL)
        XCTAssertEqual(opened.coverURL, coverURL)
        XCTAssertTrue(opened.readiumPublication.conforms(to: .epub))
    }

    func testReaderOpenDoesNotCreateOrRewriteStableCover() async throws {
        let withoutCover = try copyFixture("minimal.epub")
        let service = PublicationService()

        let firstOpened = try await service.open(at: withoutCover)

        XCTAssertNil(firstOpened.coverURL)
        let coverURL = withoutCover.deletingLastPathComponent().appendingPathComponent("cover")
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverURL.path))

        let sentinel = Data("existing cover".utf8)
        try sentinel.write(to: coverURL)
        let secondOpened = try await service.open(at: withoutCover)

        XCTAssertEqual(secondOpened.coverURL, coverURL)
        XCTAssertEqual(try Data(contentsOf: coverURL), sentinel)
    }

    func testReaderOpenSucceedsWithoutCoverInReadOnlyDirectory() async throws {
        let readOnlyDirectory = temporaryDirectory.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyDirectory, withIntermediateDirectories: true)
        let epubURL = readOnlyDirectory.appendingPathComponent("minimal.epub")
        try FileManager.default.copyItem(at: fixtureURL("minimal.epub"), to: epubURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDirectory.path)
        }

        let opened = try await PublicationService().open(at: epubURL)

        XCTAssertEqual(opened.title, "无障碍阅读示例")
        XCTAssertNil(opened.coverURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: readOnlyDirectory.appendingPathComponent("cover").path
            )
        )
    }

    func testExtractsNestedTableOfContents() async throws {
        let opened = try await PublicationService().open(at: try copyFixture("minimal.epub"))

        XCTAssertEqual(opened.tableOfContents, [
            PublicationTOCItem(
                title: "第一章 起点",
                href: "EPUB/chapter-1.xhtml",
                children: [PublicationTOCItem(title: "第一节", href: "EPUB/chapter-1.xhtml#section-1")]
            ),
            PublicationTOCItem(title: "第二章 继续", href: "EPUB/chapter-2.xhtml")
        ])
    }

    func testLoadsContinuousReaderChapterTextFromReadingOrder() async throws {
        let opened = try await PublicationService().open(at: try copyFixture("minimal.epub"))

        let references = opened.continuousChapterReferences()
        let first = try await opened.continuousChapter(for: references[0])
        let second = try await opened.continuousChapter(for: references[1])

        XCTAssertEqual(references.map(\.href), ["EPUB/chapter-1.xhtml", "EPUB/chapter-2.xhtml"])
        XCTAssertEqual(first.title, "第一章 起点")
        XCTAssertEqual(first.paragraphs, ["第一节内容。"])
        XCTAssertEqual(second.title, "第二章 继续")
        XCTAssertEqual(second.paragraphs, ["后续内容。"])
    }

    func testLocatorAndReadingPositionRoundTrip() async throws {
        let opened = try await PublicationService().open(at: try copyFixture("minimal.epub"))
        let locator = Locator(
            href: AnyURL(string: "EPUB/chapter-1.xhtml")!,
            mediaType: .xhtml,
            title: "第一章 起点",
            locations: .init(fragments: ["section-1"], progression: 0.25, totalProgression: 0.125, position: 1)
        )

        let position = try opened.readingPosition(from: locator)
        XCTAssertEqual(position.href, "EPUB/chapter-1.xhtml")
        XCTAssertEqual(position.progression, 0.125)
        XCTAssertNotNil(position.locationsJSON)

        let restored = try await opened.locator(from: position)
        XCTAssertEqual(restored.href.string, locator.href.string)
        XCTAssertEqual(restored.mediaType, locator.mediaType)
        XCTAssertEqual(restored.locations, locator.locations)
    }

    func testRestoresMissingLocationsFromWholePublicationProgression() async throws {
        let opened = try await PublicationService().open(at: try copyFixture("minimal.epub"))
        let position = ReadingPosition(
            href: "EPUB/chapter-1.xhtml",
            locationsJSON: nil,
            progression: 0.75
        )

        let restored = try await opened.locator(from: position)

        XCTAssertEqual(restored.href.string, "EPUB/chapter-2.xhtml")
        XCTAssertEqual(restored.locations.totalProgression, 0.75)
        XCTAssertNotEqual(restored.locations.progression, 0.75)
    }

    func testNormalizesLegacyPackagedHREFBeforeValidation() async throws {
        let opened = try await PublicationService().open(at: try copyFixture("minimal.epub"))
        let legacy = ReadingPosition(
            href: "/EPUB/chapter-2.xhtml",
            locationsJSON: "{\"progression\":0.2}",
            progression: 0.6
        )

        let restored = try await opened.locator(from: legacy)

        XCTAssertEqual(restored.href.string, "EPUB/chapter-2.xhtml")
        XCTAssertEqual(restored.locations.progression, 0.2)
        XCTAssertEqual(restored.locations.totalProgression, 0.6)
    }

    func testMalformedEPUBMapsToLocalizedUserError() async throws {
        do {
            _ = try await PublicationService().open(at: fixtureURL("malformed.epub"))
            XCTFail("Expected malformed EPUB to be rejected")
        } catch let error as PublicationServiceError {
            XCTAssertEqual(error, .invalidPublication)
            XCTAssertEqual(error.errorDescription, "无法打开此 EPUB，文件可能已损坏或格式不受支持。")
        }
    }

    func testProtectedEPUBIsRejectedWithoutCredentialInteraction() async throws {
        do {
            _ = try await PublicationService().open(at: fixtureURL("protected.epub"))
            XCTFail("Expected protected EPUB to be rejected")
        } catch let error as PublicationServiceError {
            XCTAssertEqual(error, .protectedPublication)
            XCTAssertEqual(error.errorDescription, "此 EPUB 受 DRM 保护，暂不支持打开。")
        }
    }

    func testMapsTypedReadiumOpenFailuresWithoutInspectingMessages() async {
        let cases: [(Error, PublicationServiceError)] = [
            (
                PublicationOpenError.reading(
                    .decoding(ContentProtectionSchemeNotSupportedError(scheme: .lcp))
                ),
                .protectedPublication
            ),
            (AssetRetrieveURLError.reading(.access(.fileSystem(.fileNotFound(nil)))), .invalidFileURL),
            (PublicationOpenError.formatNotSupported, .invalidPublication)
        ]

        for (readiumError, expected) in cases {
            let service = PublicationService(container: FailingReadiumContainer(error: readiumError))
            do {
                _ = try await service.open(at: fixtureURL("minimal.epub"))
                XCTFail("Expected typed Readium error to be mapped")
            } catch {
                XCTAssertEqual(error as? PublicationServiceError, expected)
            }
        }
    }

    private func copyFixture(_ name: String) throws -> URL {
        let destination = temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixtureURL(name), to: destination)
        return destination
    }

    private func fixtureURL(_ name: String) -> URL {
        Bundle(for: Self.self).url(
            forResource: name.replacingOccurrences(of: ".epub", with: ""),
            withExtension: "epub"
        )!
    }
}

@MainActor
private final class FailingReadiumContainer: ReadiumPublicationOpening {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func openPublication(at fileURL: URL) async throws -> Publication {
        throw error
    }
}
