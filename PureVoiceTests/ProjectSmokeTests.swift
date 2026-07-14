import XCTest

final class ProjectSmokeTests: XCTestCase {
    func testHostedAppBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.taotaoxiaoshuo.purevoice")
    }
}
