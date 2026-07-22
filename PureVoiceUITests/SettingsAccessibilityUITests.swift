import XCTest

@MainActor
final class SettingsAccessibilityUITests: XCTestCase {
    func testSettingsChangesPersistAcrossRelaunchAndReset() {
        let suite = "SettingsAccessibilityUITests-\(UUID().uuidString)"
        var app = launch(suite: suite, resets: true, contentSizeCategory: "UICTContentSizeCategoryL")
        app.tabBars.buttons["设置"].tap()

        let navigationBar = app.navigationBars["设置"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertLessThan(navigationBar.frame.height, 120)
        XCTAssertTrue(app.segmentedControls["settings.appFontSize"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["极大"].isSelected)

        let fontScale = app.sliders["settings.fontScale"]
        XCTAssertTrue(fontScale.waitForExistence(timeout: 5))
        fontScale.adjust(toNormalizedSliderPosition: 0.75)
        let persistedValue = fontScale.value as? String
        XCTAssertNotNil(persistedValue)

        app.buttons["上下滚动"].tap()
        XCTAssertTrue(app.buttons["上下滚动"].isSelected)
        app.terminate()

        app = launch(suite: suite, resets: false, contentSizeCategory: "UICTContentSizeCategoryL")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["极大"].isSelected)
        XCTAssertTrue(app.sliders["settings.fontScale"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["settings.fontScale"].value as? String, persistedValue)
        XCTAssertTrue(app.buttons["上下滚动"].isSelected)

        app.swipeUp()
        let reset = app.buttons["settings.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        reset.tap()
        app.buttons.matching(identifier: "settings.reset.confirm").firstMatch.tap()
        app.swipeDown()
        XCTAssertTrue(app.buttons["极大"].isSelected)
        XCTAssertTrue(app.buttons["左右分页"].isSelected)
    }

    func testSettingsControlsRemainReachableAtLargestDynamicType() {
        let app = launch(
            suite: "SettingsAccessibilityXXXL-\(UUID().uuidString)",
            resets: true,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        app.tabBars.buttons["设置"].tap()

        let navigationBar = app.navigationBars["设置"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertLessThan(navigationBar.frame.height, 120)
        let fontScale = app.sliders["settings.fontScale"]
        let lineHeight = app.sliders["settings.lineHeight"]
        XCTAssertTrue(lineHeight.waitForExistence(timeout: 5))
        XCTAssertFalse(fontScale.frame.intersects(lineHeight.frame))
        app.swipeUp()
        let layout = app.segmentedControls["settings.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 3))
        XCTAssertFalse(layout.frame.intersects(lineHeight.frame))
        app.swipeUp()
        XCTAssertTrue(app.sliders["settings.speechRate"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.reset"].exists)
    }

    func testReaderSettingsDirectEditsCreatePersistentBookOverrideAndToggleCanClearIt() {
        let fixture = Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub")!
        let app = launch(
            suite: "ReaderSettingsAccessibility-\(UUID().uuidString)",
            resets: true,
            contentSizeCategory: "UICTContentSizeCategoryL",
            readerFixturePath: fixture.path
        )
        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 8))
        app.buttons["reader.settings"].tap()

        let usesGlobal = app.switches["settings.useGlobal"]
        XCTAssertTrue(usesGlobal.waitForExistence(timeout: 3))
        XCTAssertEqual(usesGlobal.value as? String, "1")
        let fontScale = app.sliders["settings.fontScale"]
        fontScale.adjust(toNormalizedSliderPosition: 0.75)
        let savedFontScale = fontScale.value as? String
        app.buttons["上下滚动"].tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: usesGlobal)
        waitForExpectations(timeout: 3)
        app.buttons["settings.done"].tap()
        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 3))
        app.buttons["reader.settings"].tap()
        XCTAssertEqual(app.switches["settings.useGlobal"].value as? String, "0")
        XCTAssertTrue(app.buttons["上下滚动"].isSelected)
        XCTAssertEqual(app.sliders["settings.fontScale"].value as? String, savedFontScale)
        tapSwitch(app.switches["settings.useGlobal"])
        expectation(
            for: NSPredicate(format: "value == '1'"),
            evaluatedWith: app.switches["settings.useGlobal"]
        )
        waitForExpectations(timeout: 3)
        app.buttons["settings.done"].tap()
        showReaderChrome(in: app)
        app.buttons["reader.settings"].tap()
        XCTAssertEqual(app.switches["settings.useGlobal"].value as? String, "1")

        tapSwitch(app.switches["settings.useGlobal"])
        expectation(
            for: NSPredicate(format: "value == '0'"),
            evaluatedWith: app.switches["settings.useGlobal"]
        )
        waitForExpectations(timeout: 3)
    }

    func testReaderSheetsFollowAppFontSizeSetting() {
        let suite = "ReaderSheetsAppFontSize-\(UUID().uuidString)"
        var app = launch(
            suite: suite,
            resets: true,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appFontSize"].waitForExistence(timeout: 5))
        app.buttons["小"].tap()
        app.terminate()

        let fixture = Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub")!
        app = launch(
            suite: suite,
            resets: false,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL",
            readerFixturePath: fixture.path
        )
        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 8))
        app.buttons["reader.settings"].tap()

        let useGlobal = app.switches["settings.useGlobal"]
        XCTAssertTrue(useGlobal.waitForExistence(timeout: 3))
        XCTAssertLessThan(useGlobal.frame.height, 56)
        app.buttons["settings.done"].tap()

        showReaderChrome(in: app)
        app.buttons["reader.tableOfContents"].tap()
        let tocEntry = app.buttons["reader.toc.0"]
        XCTAssertTrue(tocEntry.waitForExistence(timeout: 3))
        XCTAssertLessThan(tocEntry.frame.height, 64)
    }

    private func launch(
        suite: String,
        resets: Bool,
        contentSizeCategory: String,
        readerFixturePath: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", contentSizeCategory]
        app.launchEnvironment["PUREVOICE_UI_TEST_SETTINGS_SUITE"] = suite
        app.launchEnvironment["PUREVOICE_UI_TEST_SETTINGS_RESET"] = resets ? "1" : "0"
        if let readerFixturePath {
            app.launchEnvironment["PUREVOICE_UI_TEST_READER_EPUB"] = readerFixturePath
        }
        app.launch()
        return app
    }

    private func tapSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func showReaderChrome(in app: XCUIApplication) {
        if app.buttons["reader.listen"].exists || app.buttons["reader.back"].exists {
            return
        }
        if app.otherElements["reader.chrome"].exists {
            return
        }
        let hotZone = app.buttons["reader.contentTapArea"]
        if hotZone.waitForExistence(timeout: 3) {
            hotZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }
}
