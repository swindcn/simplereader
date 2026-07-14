import XCTest
@testable import PureVoice

final class BookFormatDetectorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookFormatDetectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testExtensionsAreCaseInsensitiveAndAZWVariantsMapToMOBI() throws {
        let cases: [(String, BookFormat)] = [
            ("book.TXT", .txt),
            ("book.EpUb", .epub),
            ("book.MOBI", .mobi),
            ("book.AzW", .mobi),
            ("book.aZw3", .mobi)
        ]

        for (name, expected) in cases {
            let url = try write(Data("ordinary content".utf8), named: name)
            XCTAssertEqual(try BookFormatDetector().detect(at: url), expected, name)
        }
    }

    func testEveryZIPSignatureOverridesMisleadingExtension() throws {
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04],
            [0x50, 0x4B, 0x05, 0x06],
            [0x50, 0x4B, 0x07, 0x08]
        ]

        for (index, signature) in signatures.enumerated() {
            let url = try write(Data(signature + [0, 1, 2]), named: "misleading-\(index).txt")
            XCTAssertEqual(try BookFormatDetector().detect(at: url), .epub)
        }
    }

    func testPalmDBSignatureOverridesMisleadingExtension() throws {
        var bytes = [UInt8](repeating: 0, count: 68)
        bytes.replaceSubrange(60...67, with: Array("BOOKMOBI".utf8))
        let url = try write(Data(bytes), named: "misleading.epub")

        XCTAssertEqual(try BookFormatDetector().detect(at: url), .mobi)
    }

    func testUnsignedPlainTextUsesExtension() throws {
        let url = try write(Data("hello".utf8), named: "novel.txt")

        XCTAssertEqual(try BookFormatDetector().detect(at: url), .txt)
    }

    func testUnsupportedUnsignedFileHasExplicitError() throws {
        let url = try write(Data("hello".utf8), named: "novel.pdf")

        XCTAssertThrowsError(try BookFormatDetector().detect(at: url)) { error in
            XCTAssertEqual(error as? BookFormatDetectionError, .unsupportedExtension("pdf"))
        }
    }

    func testShortAndEmptyFilesAreSafe() throws {
        let oneByte = try write(Data([0x50]), named: "short.txt")
        let empty = try write(Data(), named: "empty.azw3")

        XCTAssertEqual(try BookFormatDetector().detect(at: oneByte), .txt)
        XCTAssertEqual(try BookFormatDetector().detect(at: empty), .mobi)
    }

    func testReadsOnlyBoundedHeaderFromCopiedFile() throws {
        let url = temporaryDirectory.appendingPathComponent("large.epub")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x50, 0x4B, 0x03, 0x04])))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 512 * 1_024 * 1_024)
        try handle.close()

        let detector = BookFormatDetector(maximumHeaderBytes: 68)

        XCTAssertEqual(try detector.detect(at: url), .epub)
        XCTAssertEqual(detector.maximumHeaderBytes, 68)
    }

    func testIOFailureIsMappedClearly() {
        let missing = temporaryDirectory.appendingPathComponent("missing.txt")

        XCTAssertThrowsError(try BookFormatDetector().detect(at: missing)) { error in
            guard case let BookFormatDetectionError.unreadableFile(path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, missing.path)
        }
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
