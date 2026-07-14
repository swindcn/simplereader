import XCTest

@MainActor
final class LibraryAccessibilityUITests: XCTestCase {
    func testSeededLibraryExposesCombinedBookActionsAndFixedTabs() {
        assertSeededLibrary(contentSizeCategory: "UICTContentSizeCategoryL")
    }

    func testSeededLibraryAtLargestAccessibilityTextSize() {
        assertSeededLibrary(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func assertSeededLibrary(contentSizeCategory: String?) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launchEnvironment["PUREVOICE_UI_TEST_LIBRARY_SEED"] = "1"
        app.launch()
        app.terminate()
        app.launch()

        let continueBook = app.buttons["library.continue.book.11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(continueBook.waitForExistence(timeout: 3))
        XCTAssertEqual(continueBook.label, "活着，余华，已读百分之三十五")

        for id in [
            "22222222-2222-2222-2222-222222222222",
            "33333333-3333-3333-3333-333333333333",
            "44444444-4444-4444-4444-444444444444"
        ] {
            XCTAssertTrue(app.buttons["library.recent.book.\(id)"].exists)
        }

        XCTAssertEqual(continueBook.images.count, 0)
        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        XCTAssertTrue(app.tabBars.buttons["导入"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
        XCTAssertFalse(app.tabBars.buttons["听书"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = contentSizeCategory == "UICTContentSizeCategoryL"
            ? "Library-Standard"
            : "Library-Accessibility-XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
