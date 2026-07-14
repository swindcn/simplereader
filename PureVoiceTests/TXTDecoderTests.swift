import XCTest
import CoreFoundation
@testable import PureVoice

final class TXTDecoderTests: XCTestCase {
    private let decoder = TXTDecoder()

    func testDecodesUTF8Fixture() throws {
        let text = try decoder.decode(data: fixtureData("utf8-novel.txt"))
        XCTAssertTrue(text.contains("第十二章 重逢"))
        XCTAssertTrue(text.contains("English <body> & Chinese 正文。"))
    }

    func testDecodesGB18030Fixture() throws {
        let text = try decoder.decode(data: fixtureData("gb18030-novel.txt"))
        XCTAssertTrue(text.contains("第一章 花开"))
        XCTAssertTrue(text.contains("这是GB18030中文内容。"))
    }

    func testDecodesUTF16WithBOMInBothByteOrders() throws {
        let expected = "第一章\n你好，世界"
        let littleEndian = Data([0xFF, 0xFE]) + expected.data(using: .utf16LittleEndian)!
        let bigEndian = Data([0xFE, 0xFF]) + expected.data(using: .utf16BigEndian)!
        XCTAssertEqual(try decoder.decode(data: littleEndian), expected)
        XCTAssertEqual(try decoder.decode(data: bigEndian), expected)
    }

    func testDecodesUTF16WithoutBOMOnlyWhenByteOrderSignalIsReliable() throws {
        let expected = "Chapter 1\n你好"
        XCTAssertEqual(try decoder.decode(data: expected.data(using: .utf16LittleEndian)!), expected)
        XCTAssertEqual(try decoder.decode(data: expected.data(using: .utf16BigEndian)!), expected)
    }

    func testDoesNotMisclassifyEvenLengthLegacyBytesAsUTF16() throws {
        let data = "第一章 花开".data(using: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))!
        XCTAssertEqual(try decoder.decode(data: data), "第一章 花开")
    }

    func testRejectsEmptyAndInvalidDataWithStructuredError() {
        XCTAssertThrowsError(try decoder.decode(data: Data())) { XCTAssertEqual($0 as? TXTDecodingError, .emptyFile) }
        XCTAssertThrowsError(try decoder.decode(data: Data(repeating: 0, count: 32))) { error in
            XCTAssertEqual(error as? TXTDecodingError, .unsupportedEncoding)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }

    private func fixtureData(_ name: String) -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures/txt")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/txt/\(name)")
        return try! Data(contentsOf: url)
    }
}
