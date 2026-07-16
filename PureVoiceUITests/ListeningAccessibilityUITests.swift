import XCTest

@MainActor
final class ListeningAccessibilityUITests: XCTestCase {
    func testReaderOpensListeningControlsAndMiniPlayerRemainsReachable() {
        let app = launchListening(contentSizeCategory: "UICTContentSizeCategoryL")

        let playPause = app.buttons["listening.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["listening.previous"].label, "上一句")
        XCTAssertEqual(app.buttons["listening.next"].label, "下一句")
        XCTAssertEqual(playPause.label, "暂停")

        playPause.tap()
        XCTAssertEqual(playPause.label, "播放")
        app.buttons["listening.previous"].tap()
        app.buttons["listening.next"].tap()
        XCTAssertEqual(playPause.label, "暂停")
        playPause.tap()
        XCTAssertEqual(playPause.label, "播放")

        let rate = app.sliders["listening.rate"]
        XCTAssertTrue(rate.exists)
        rate.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertFalse(rate.value as? String == nil)
        app.swipeUp()
        let voice = app.pickerWheels.firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 3))
        XCTAssertEqual(voice.value as? String, "系统默认")
        let initialVoice = voice.value as? String
        let targetVoice = initialVoice == "小语，女声" ? "小宇，男声" : "小语，女声"
        voice.adjust(toPickerWheelValue: targetVoice)
        XCTAssertEqual(voice.value as? String, targetVoice)
        XCTAssertNotEqual(voice.value as? String, initialVoice)

        app.buttons["listening.back"].tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.otherElements.matching(identifier: "miniPlayer").count, 1)
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].exists)
        app.buttons["miniPlayer.open"].tap()
        XCTAssertTrue(app.buttons["listening.back"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["listening.playPause"].label, "播放")

        app.buttons["listening.back"].tap()
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 3))
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.navigationBars["我的书架"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["miniPlayer"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.otherElements.matching(identifier: "miniPlayer").count, 1)
        app.buttons["miniPlayer.open"].tap()
        XCTAssertTrue(app.buttons["listening.back"].waitForExistence(timeout: 3))
    }

    func testListeningPrimaryControlsDoNotOverlapAtLargestTextSize() {
        let app = launchListening(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        let previous = app.buttons["listening.previous"]
        let playPause = app.buttons["listening.playPause"]
        let next = app.buttons["listening.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))

        for element in [previous, playPause, next] {
            XCTAssertGreaterThanOrEqual(element.frame.width, 43.9)
            XCTAssertGreaterThanOrEqual(element.frame.height, 43.9)
        }
        XCTAssertFalse(previous.frame.intersects(playPause.frame))
        XCTAssertFalse(playPause.frame.intersects(next.frame))
        XCTAssertTrue(app.sliders["listening.rate"].exists)
        app.swipeUp()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 3))
    }

    private func launchListening(contentSizeCategory: String) -> XCUIApplication {
        let fixture = Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub")!
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", contentSizeCategory]
        app.launchEnvironment["PUREVOICE_UI_TEST_READER_EPUB"] = fixture.path
        app.launchEnvironment["PUREVOICE_UI_TEST_LISTENING"] = "1"
        app.launchEnvironment["PUREVOICE_UI_TEST_SETTINGS_SUITE"] = "ListeningAccessibilityUITests-\(UUID().uuidString)"
        app.launchEnvironment["PUREVOICE_UI_TEST_SETTINGS_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["reader.listen"].waitForExistence(timeout: 8))
        app.buttons["reader.listen"].tap()
        return app
    }
}
