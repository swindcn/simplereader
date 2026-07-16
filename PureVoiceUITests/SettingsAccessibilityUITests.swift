import XCTest

@MainActor
final class SettingsAccessibilityUITests: XCTestCase {
    func testSettingsChangesPersistAcrossRelaunchAndReset() {
        let suite = "SettingsAccessibilityUITests-\(UUID().uuidString)"
        var app = launch(suite: suite, resets: true, contentSizeCategory: "UICTContentSizeCategoryL")
        app.tabBars.buttons["设置"].tap()

        let fontScale = app.sliders["settings.fontScale"]
        XCTAssertTrue(fontScale.waitForExistence(timeout: 5))
        fontScale.adjust(toNormalizedSliderPosition: 0.75)
        let persistedValue = fontScale.value as? String
        XCTAssertNotNil(persistedValue)

        app.buttons["滚动"].tap()
        XCTAssertTrue(app.buttons["滚动"].isSelected)
        app.terminate()

        app = launch(suite: suite, resets: false, contentSizeCategory: "UICTContentSizeCategoryL")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.sliders["settings.fontScale"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["settings.fontScale"].value as? String, persistedValue)
        XCTAssertTrue(app.buttons["滚动"].isSelected)

        app.swipeUp()
        let reset = app.buttons["settings.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        reset.tap()
        app.buttons.matching(identifier: "settings.reset.confirm").firstMatch.tap()
        app.swipeDown()
        XCTAssertTrue(app.buttons["分页"].isSelected)
    }

    func testSettingsControlsRemainReachableAtLargestDynamicType() {
        let app = launch(
            suite: "SettingsAccessibilityXXXL-\(UUID().uuidString)",
            resets: true,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        app.tabBars.buttons["设置"].tap()

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
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 8))
        app.buttons["reader.settings"].tap()

        let usesGlobal = app.switches["settings.useGlobal"]
        XCTAssertTrue(usesGlobal.waitForExistence(timeout: 3))
        XCTAssertEqual(usesGlobal.value as? String, "1")
        let fontScale = app.sliders["settings.fontScale"]
        fontScale.adjust(toNormalizedSliderPosition: 0.75)
        let savedFontScale = fontScale.value as? String
        app.buttons["滚动"].tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: usesGlobal)
        waitForExpectations(timeout: 3)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 3))
        app.buttons["reader.settings"].tap()
        XCTAssertEqual(app.switches["settings.useGlobal"].value as? String, "0")
        XCTAssertTrue(app.buttons["滚动"].isSelected)
        XCTAssertEqual(app.sliders["settings.fontScale"].value as? String, savedFontScale)
        tapSwitch(app.switches["settings.useGlobal"])
        expectation(
            for: NSPredicate(format: "value == '1'"),
            evaluatedWith: app.switches["settings.useGlobal"]
        )
        waitForExpectations(timeout: 3)
        app.buttons["settings.done"].tap()
        app.buttons["reader.settings"].tap()
        XCTAssertEqual(app.switches["settings.useGlobal"].value as? String, "1")

        tapSwitch(app.switches["settings.useGlobal"])
        expectation(
            for: NSPredicate(format: "value == '0'"),
            evaluatedWith: app.switches["settings.useGlobal"]
        )
        waitForExpectations(timeout: 3)
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
}
