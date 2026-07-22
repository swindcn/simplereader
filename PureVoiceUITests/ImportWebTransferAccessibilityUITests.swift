import XCTest

final class ImportWebTransferAccessibilityUITests: XCTestCase {
    func testImportTabExposesWebTransferControls() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["导入"].tap()

        XCTAssertTrue(app.staticTexts["网站传书"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["网站地址"].exists)
        XCTAssertTrue(app.staticTexts["设备传书 ID"].exists)
        XCTAssertTrue(app.buttons["生成传书码"].exists)
        XCTAssertTrue(app.buttons["复制网站地址"].exists)
        XCTAssertTrue(app.buttons["刷新"].exists)
    }
}
