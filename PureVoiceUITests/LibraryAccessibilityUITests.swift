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

        let recentButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library.recent.book.")
        )
        XCTAssertEqual(recentButtons.count, 3)
        XCTAssertFalse(
            app.buttons["library.recent.book.11111111-1111-1111-1111-111111111111"].exists
        )

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

        let scrollView = app.scrollViews.firstMatch
        let tabBar = app.tabBars.firstMatch
        let firstRecentBook = app.buttons[
            "library.recent.book.22222222-2222-2222-2222-222222222222"
        ]
        let lastRecentBook = app.buttons[
            "library.recent.book.44444444-4444-4444-4444-444444444444"
        ]
        XCTAssertTrue(scrollView.exists)
        XCTAssertTrue(tabBar.exists)
        if firstRecentBook.frame.insetBy(dx: 0, dy: 2).intersects(tabBar.frame) {
            let dragStart = scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)
            )
            let dragEnd = scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)
            )
            dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        }

        let firstRecentFrame = firstRecentBook.frame.insetBy(dx: 0, dy: 2)
        XCTAssertFalse(
            firstRecentFrame.intersects(tabBar.frame),
            "First recent book \(firstRecentFrame) must remain above tab bar \(tabBar.frame)"
        )
        XCTAssertGreaterThanOrEqual(firstRecentFrame.minY, scrollView.frame.minY - 2)

        for _ in 0..<4 {
            scrollView.swipeUp()
        }

        let visibleBookFrame = lastRecentBook.frame.insetBy(dx: 0, dy: 2)
        XCTAssertGreaterThan(visibleBookFrame.width, 0)
        XCTAssertGreaterThanOrEqual(visibleBookFrame.minY, scrollView.frame.minY - 2)
        XCTAssertFalse(
            visibleBookFrame.intersects(tabBar.frame),
            "Last recent book \(visibleBookFrame) must remain above tab bar \(tabBar.frame)"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = contentSizeCategory == "UICTContentSizeCategoryL"
            ? "Library-Standard"
            : "Library-Accessibility-XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
