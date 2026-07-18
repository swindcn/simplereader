import UniformTypeIdentifiers
import XCTest
@testable import PureVoice

final class DocumentPickerTests: XCTestCase {
    func testShippingPickerOnlyAdvertisesTXTAndEPUB() {
        XCTAssertEqual(DocumentPicker.supportedContentTypes, [.plainText, .epub])
    }
}
