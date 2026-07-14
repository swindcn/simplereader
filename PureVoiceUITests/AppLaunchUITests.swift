import XCTest

final class AppLaunchUITests: XCTestCase {
    func testFixedTabsAreVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        XCTAssertTrue(app.tabBars.buttons["导入"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
        XCTAssertFalse(app.tabBars.buttons["听书"].exists)
    }
}
