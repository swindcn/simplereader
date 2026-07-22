import XCTest

@MainActor
final class ImportWebTransferAccessibilityUITests: XCTestCase {
    func testImportTabExposesWebTransferControls() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["导入"].tap()

        let navigationBar = app.navigationBars["导入书籍"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertLessThan(navigationBar.frame.height, 120)
        XCTAssertTrue(app.staticTexts["网站传书"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["传书码"].exists)
        XCTAssertTrue(app.staticTexts["传书网址"].exists)
        XCTAssertTrue(app.buttons["复制传书网址"].exists)
    }
}
