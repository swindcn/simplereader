import XCTest
@testable import PureVoice

final class ImportPipelineConverterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportPipelineConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testEPUBPassThroughCopiesSourceBytesToPublicationEPUB() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.epub")
        let destination = temporaryDirectory
            .appendingPathComponent("Book", isDirectory: true)
            .appendingPathComponent("publication.epub")
        let bytes = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x01, 0x02, 0x03])
        try bytes.write(to: source)

        try await ImportPipelineConverter().convert(
            originalURL: source,
            format: .epub,
            suggestedTitle: "Source",
            destinationURL: destination
        )

        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(destination.lastPathComponent, "publication.epub")
    }

    func testTXTDelegatesToTXTCanonicalConverter() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        let destination = temporaryDirectory.appendingPathComponent("publication.epub")
        try Data("正文".utf8).write(to: source)
        let txtConverter = RecordingPipelineConverter()
        let converter = ImportPipelineConverter(txtConverter: txtConverter)

        try await converter.convert(
            originalURL: source,
            format: .txt,
            suggestedTitle: "章节标题",
            destinationURL: destination
        )

        let recordedCall = await txtConverter.call()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.originalURL, source)
        XCTAssertEqual(call.format, .txt)
        XCTAssertEqual(call.suggestedTitle, "章节标题")
        XCTAssertEqual(call.destinationURL, destination)
    }

    func testMOBIStaysUnsupportedInPipeline() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.mobi")
        let destination = temporaryDirectory.appendingPathComponent("publication.epub")
        try Data("mobi".utf8).write(to: source)

        do {
            try await ImportPipelineConverter().convert(
                originalURL: source,
                format: .mobi,
                suggestedTitle: "MOBI",
                destinationURL: destination
            )
            XCTFail("MOBI should remain gated before canonical conversion")
        } catch let error as TXTConversionError {
            XCTAssertEqual(error, .unsupportedFormat(.mobi))
        }
    }
}

private actor RecordingPipelineConverter: CanonicalPublicationConverting {
    private(set) var recordedCall: Call?

    func convert(
        originalURL: URL,
        format: BookFormat,
        suggestedTitle: String,
        destinationURL: URL
    ) async throws {
        recordedCall = Call(
            originalURL: originalURL,
            format: format,
            suggestedTitle: suggestedTitle,
            destinationURL: destinationURL
        )
    }

    func call() -> Call? { recordedCall }

    struct Call: Equatable {
        let originalURL: URL
        let format: BookFormat
        let suggestedTitle: String
        let destinationURL: URL
    }
}
