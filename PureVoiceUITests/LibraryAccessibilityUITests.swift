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

        let shelfButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library.shelf.book.")
        )
        XCTAssertEqual(shelfButtons.count, 3)
        XCTAssertFalse(
            app.buttons["library.shelf.book.11111111-1111-1111-1111-111111111111"].exists
        )

        let firstShelfBook = app.buttons["library.shelf.book.22222222-2222-2222-2222-222222222222"]
        let secondShelfBook = app.buttons["library.shelf.book.33333333-3333-3333-3333-333333333333"]
        let lastShelfBook = app.buttons["library.shelf.book.44444444-4444-4444-4444-444444444444"]
        XCTAssertEqual(firstShelfBook.label, "许三观卖血记，余华，已读百分之六十二")
        XCTAssertEqual(secondShelfBook.label, "围城，钱钟书，已读百分之十二")
        XCTAssertEqual(lastShelfBook.label, "平凡的世界，路遥，已读百分之一百")

        XCTAssertEqual(continueBook.images.count, 0)
        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        XCTAssertTrue(app.tabBars.buttons["导入"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)
        XCTAssertFalse(app.tabBars.buttons["听书"].exists)

        let scrollView = app.scrollViews.firstMatch
        let header = app.otherElements["library.header"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(scrollView.exists)
        XCTAssertTrue(header.exists)
        XCTAssertTrue(tabBar.exists)
        if firstShelfBook.frame.insetBy(dx: 0, dy: 2).intersects(tabBar.frame) {
            let dragStart = scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)
            )
            let dragEnd = scrollView.coordinate(
                withNormalizedOffset: CGVector(
                    dx: 0.5,
                    dy: contentSizeCategory == "UICTContentSizeCategoryL" ? 0.52 : 0.25
                )
            )
            dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        }

        let firstRecentFrame = firstShelfBook.frame.insetBy(dx: 0, dy: 2)
        XCTAssertFalse(
            firstRecentFrame.intersects(tabBar.frame),
            "First recent book \(firstRecentFrame) must remain above tab bar \(tabBar.frame)"
        )

        var viewportBook = firstShelfBook
        if contentSizeCategory != "UICTContentSizeCategoryL" {
            let dragStart = scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70)
            )
            let dragEnd = scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.29)
            )
            dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
            viewportBook = secondShelfBook
        }

        position(
            viewportBook,
            in: scrollView,
            between: header,
            and: tabBar
        )
        let viewportBookFrame = viewportBook.frame.insetBy(dx: 0, dy: 2)
        XCTAssertGreaterThanOrEqual(viewportBookFrame.minY, header.frame.maxY - 2)
        XCTAssertLessThanOrEqual(viewportBookFrame.maxY, tabBar.frame.minY + 2)

        Thread.sleep(forTimeInterval: 1)
        let viewportScreenshot = XCTAttachment(screenshot: app.screenshot())
        viewportScreenshot.name = contentSizeCategory == "UICTContentSizeCategoryL"
            ? "Library-Standard-Navigation-Clear"
            : "Library-Accessibility-XXXL-Navigation-Clear"
        viewportScreenshot.lifetime = .keepAlways
        add(viewportScreenshot)

        for _ in 0..<4 {
            scrollView.swipeUp()
        }

        let visibleBookFrame = lastShelfBook.frame.insetBy(dx: 0, dy: 2)
        XCTAssertGreaterThan(visibleBookFrame.width, 0)
        XCTAssertGreaterThanOrEqual(visibleBookFrame.minY, header.frame.maxY - 2)
        XCTAssertFalse(
            visibleBookFrame.intersects(tabBar.frame),
            "Last recent book \(visibleBookFrame) must remain above tab bar \(tabBar.frame)"
        )

        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = contentSizeCategory == "UICTContentSizeCategoryL"
            ? "Library-Standard-Last-Book"
            : "Library-Accessibility-XXXL-Last-Book"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func position(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        between navigationBar: XCUIElement,
        and tabBar: XCUIElement
    ) {
        let padding: CGFloat = 12

        for _ in 0..<6 {
            let frame = element.frame.insetBy(dx: 0, dy: 2)
            let top = navigationBar.frame.maxY + padding
            let bottom = tabBar.frame.minY - padding
            let scrollHeight = scrollView.frame.height

            if frame.minY < top {
                let distance = min(max(top - frame.minY, 28), scrollHeight * 0.12)
                let start = scrollView.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)
                )
                let end = scrollView.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42 + distance / scrollHeight)
                )
                start.press(forDuration: 0.1, thenDragTo: end)
            } else if frame.maxY > bottom {
                let distance = min(max(frame.maxY - bottom, 28), scrollHeight * 0.12)
                let start = scrollView.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)
                )
                let end = scrollView.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58 - distance / scrollHeight)
                )
                start.press(forDuration: 0.1, thenDragTo: end)
            } else {
                return
            }
        }
    }
}
