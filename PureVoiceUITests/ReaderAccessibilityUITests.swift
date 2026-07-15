import XCTest

@MainActor
final class ReaderAccessibilityUITests: XCTestCase {
    func testReaderControlsAndTableOfContentsAreAccessible() throws {
        let app = launchReader(contentSizeCategory: "UICTContentSizeCategoryL")

        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["reader.back"].label, "返回书架")
        XCTAssertEqual(app.buttons["reader.tableOfContents"].label, "目录")
        XCTAssertEqual(app.buttons["reader.previousPage"].label, "上一页")
        XCTAssertEqual(app.buttons["reader.nextPage"].label, "下一页")
        XCTAssertEqual(app.buttons["reader.listen"].label, "听书")
        XCTAssertEqual(app.buttons["reader.settings"].label, "设置")
        XCTAssertTrue(app.staticTexts["reader.chapterHeading"].exists)

        let locatorProbe = app.staticTexts["reader.debug.locator"]
        XCTAssertTrue(locatorProbe.waitForExistence(timeout: 4))
        let located = NSPredicate(format: "label != %@", "等待定位")
        expectation(for: located, evaluatedWith: locatorProbe)
        waitForExpectations(timeout: 4)
        let initialLocator = locatorProbe.label
        app.buttons["reader.nextPage"].tap()
        let moved = NSPredicate(format: "label != %@", initialLocator)
        expectation(for: moved, evaluatedWith: locatorProbe)
        waitForExpectations(timeout: 4)
        app.buttons["reader.previousPage"].tap()

        app.buttons["reader.tableOfContents"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["reader.toc.1"].exists)
        app.buttons["reader.toc.1"].tap()
        let chapterHeading = app.staticTexts["reader.chapterHeading"]
        XCTAssertTrue(chapterHeading.waitForExistence(timeout: 2))
        XCTAssertEqual(chapterHeading.label, "第二章 继续")
    }

    func testReaderControlsDoNotOverlapAtLargestAccessibilityTextSize() throws {
        let longHeading = "这是一个用于验证最大动态字体多行布局不会被截断的很长章节标题"
        let app = launchReader(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL",
            headingOverride: longHeading
        )
        let previous = app.buttons["reader.previousPage"]
        let next = app.buttons["reader.nextPage"]
        let listen = app.buttons["reader.listen"]
        let settings = app.buttons["reader.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))

        for element in [previous, next, listen, settings] {
            XCTAssertGreaterThanOrEqual(element.frame.width, 43.9)
            XCTAssertGreaterThanOrEqual(element.frame.height, 43.9)
        }
        XCTAssertFalse(previous.frame.intersects(next.frame))
        XCTAssertFalse(next.frame.intersects(listen.frame))
        XCTAssertFalse(listen.frame.intersects(settings.frame))

        let heading = app.staticTexts["reader.chapterHeading"]
        XCTAssertEqual(heading.label, longHeading)
        XCTAssertGreaterThan(heading.frame.height, 52)
        XCTAssertFalse(heading.frame.intersects(app.buttons["reader.back"].frame))
        XCTAssertFalse(heading.frame.intersects(app.buttons["reader.tableOfContents"].frame))
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
}
