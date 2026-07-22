import XCTest

@MainActor
final class ReaderAccessibilityUITests: XCTestCase {
    func testReaderControlsAndTableOfContentsAreAccessible() throws {
        let app = launchReader(contentSizeCategory: "UICTContentSizeCategoryL")

        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["reader.back"].label, "返回书架")
        XCTAssertEqual(app.buttons["reader.tableOfContents"].label, "目录")
        XCTAssertFalse(app.buttons["reader.previousPage"].exists)
        XCTAssertFalse(app.buttons["reader.nextPage"].exists)
        XCTAssertEqual(app.buttons["reader.listen"].label, "听书")
        XCTAssertEqual(app.buttons["reader.settings"].label, "设置")
        XCTAssertTrue(app.staticTexts["reader.chapterHeading"].exists)

        let locatorProbe = app.staticTexts["reader.debug.locator"]
        XCTAssertTrue(locatorProbe.waitForExistence(timeout: 4))
        let located = NSPredicate(format: "label != %@", "等待定位")
        expectation(for: located, evaluatedWith: locatorProbe)
        waitForExpectations(timeout: 4)
        showReaderChrome(in: app)
        app.buttons["reader.tableOfContents"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["reader.toc.1"].exists)
        app.buttons["reader.toc.1"].tap()
        let chapterHeading = app.staticTexts["第二章 继续"]
        XCTAssertTrue(chapterHeading.waitForExistence(timeout: 2))
        XCTAssertEqual(chapterHeading.label, "第二章 继续")
    }

    func testReaderControlsDoNotOverlapAtLargestAccessibilityTextSize() throws {
        let longHeading = "这是一个用于验证最大动态字体多行布局不会被截断的很长章节标题"
        let app = launchReader(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL",
            headingOverride: longHeading
        )
        XCTAssertTrue(app.buttons["reader.contentTapArea"].waitForExistence(timeout: 5))
        showReaderChrome(in: app)
        let listen = app.buttons["reader.listen"]
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))

        for element in [listen, settings] {
            XCTAssertGreaterThanOrEqual(element.frame.width, 43.9)
            XCTAssertGreaterThanOrEqual(element.frame.height, 43.9)
        }
        XCTAssertFalse(listen.frame.intersects(settings.frame))

        let heading = app.staticTexts["reader.chapterHeading"]
        XCTAssertEqual(heading.label, longHeading)
        XCTAssertGreaterThan(heading.frame.height, 52)
        XCTAssertFalse(heading.frame.intersects(app.buttons["reader.back"].frame))
        XCTAssertFalse(heading.frame.intersects(app.buttons["reader.tableOfContents"].frame))
    }

    func testReaderChromeAutoHidesAndReturnsFromContentTap() throws {
        let app = launchReader(contentSizeCategory: "UICTContentSizeCategoryL")

        XCTAssertTrue(app.otherElements["reader.chrome"].waitForExistence(timeout: 8))
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: app.otherElements["reader.chrome"])
        waitForExpectations(timeout: 4)

        XCTAssertTrue(app.buttons["reader.contentTapArea"].waitForExistence(timeout: 2))
        XCTAssertLessThan(app.buttons["reader.contentTapArea"].frame.maxY, app.frame.height * 0.5)
        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 4))
    }

    func testReaderContentFrameDoesNotChangeWhenChromeToggles() throws {
        let app = launchReader(contentSizeCategory: "UICTContentSizeCategoryL")
        let content = app.otherElements["阅读内容"]
        XCTAssertTrue(content.waitForExistence(timeout: 8))

        let visibleFrame = content.frame
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: app.otherElements["reader.chrome"])
        waitForExpectations(timeout: 4)
        XCTAssertEqual(content.frame, visibleFrame)

        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 4))
        XCTAssertEqual(content.frame, visibleFrame)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        expectation(for: hidden, evaluatedWith: app.otherElements["reader.chrome"])
        waitForExpectations(timeout: 2)
        XCTAssertEqual(content.frame, visibleFrame)
    }

    private func launchReader(
        contentSizeCategory: String,
        headingOverride: String? = nil
    ) -> XCUIApplication {
        let fixture = Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub")!
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", contentSizeCategory]
        app.launchEnvironment["PUREVOICE_UI_TEST_READER_EPUB"] = fixture.path
        if let headingOverride {
            app.launchEnvironment["PUREVOICE_UI_TEST_READER_HEADING"] = headingOverride
        }
        app.launch()
        return app
    }

    private func showReaderChrome(in app: XCUIApplication) {
        let hotZone = app.buttons["reader.contentTapArea"]
        if hotZone.waitForExistence(timeout: 1) {
            hotZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }
}
