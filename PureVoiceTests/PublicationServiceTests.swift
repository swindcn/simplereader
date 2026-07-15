import enum ReadiumShared.AnyURL
import struct ReadiumShared.Locator
import struct ReadiumShared.MediaType
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

        let opened = try await service.open(at: epubURL)

        XCTAssertEqual(opened.title, "无障碍阅读示例")
        XCTAssertEqual(opened.author, "示例作者")
        XCTAssertEqual(opened.coverURL, epubURL.deletingLastPathComponent().appendingPathComponent("cover.png"))
        let coverURL = try XCTUnwrap(opened.coverURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverURL.path))
        XCTAssertFalse(try Data(contentsOf: coverURL).isEmpty)

        let metadata = try await service.openPublication(at: epubURL)
        XCTAssertEqual(metadata, PublicationMetadata(title: "无障碍阅读示例", author: "示例作者", coverURL: coverURL))
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

        let restored = try opened.locator(from: position)
        XCTAssertEqual(restored.href.string, locator.href.string)
        XCTAssertEqual(restored.mediaType, locator.mediaType)
        XCTAssertEqual(restored.locations, locator.locations)
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
