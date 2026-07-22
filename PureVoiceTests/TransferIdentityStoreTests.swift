import XCTest
@testable import PureVoice

final class TransferIdentityStoreTests: XCTestCase {
    func testMemoryStoreCreatesStableIdentityUntilReset() throws {
        let store = InMemoryTransferIdentityStore()

        let first = try store.identity()
        let second = try store.identity()

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.deviceSecret.count, 32)

        try store.reset()
        let reset = try store.identity()

        XCTAssertNotEqual(reset.deviceID, first.deviceID)
        XCTAssertNotEqual(reset.deviceSecret, first.deviceSecret)
    }
}
