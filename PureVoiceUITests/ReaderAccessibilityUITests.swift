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

        app.buttons["reader.nextPage"].tap()
        app.buttons["reader.previousPage"].tap()

        app.buttons["reader.tableOfContents"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["reader.toc.EPUB/chapter-2.xhtml"].exists)
        app.buttons["reader.toc.EPUB/chapter-2.xhtml"].tap()
        let chapterHeading = app.staticTexts["reader.chapterHeading"]
        XCTAssertTrue(chapterHeading.waitForExistence(timeout: 2))
        XCTAssertEqual(chapterHeading.label, "第二章 继续")
    }

    func testReaderControlsDoNotOverlapAtLargestAccessibilityTextSize() throws {
        let app = launchReader(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
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
    }

    private func launchReader(contentSizeCategory: String) -> XCUIApplication {
        let fixture = Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub")!
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", contentSizeCategory]
        app.launchEnvironment["PUREVOICE_UI_TEST_READER_EPUB"] = fixture.path
        app.launch()
        return app
    }
}
