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
        XCTAssertFalse(app.pickerWheels.firstMatch.exists)
        let voice = app.buttons["listening.voice"]
        XCTAssertTrue(voice.waitForExistence(timeout: 3))
        XCTAssertEqual(voice.label, "声音")
        XCTAssertEqual(voice.value as? String, "系统默认")
        voice.tap()
        XCTAssertTrue(app.sheets["选择声音"].waitForExistence(timeout: 3))
        app.buttons["小语，女声"].tap()
        waitForValue(of: voice, toBe: "小语，女声", timeout: 3)
        XCTAssertEqual(voice.value as? String, "小语，女声")

        app.buttons["listening.back"].tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.otherElements.matching(identifier: "miniPlayer").count, 1)
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].exists)
        XCTAssertTrue(app.buttons["miniPlayer.close"].exists)
        app.buttons["miniPlayer.open"].tap()
        XCTAssertTrue(app.buttons["listening.back"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["listening.playPause"].label, "播放")

        app.buttons["listening.back"].tap()
        showReaderChrome(in: app)
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 3))
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.staticTexts["简声"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["miniPlayer"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.otherElements.matching(identifier: "miniPlayer").count, 1)
        app.buttons["miniPlayer.close"].tap()
        XCTAssertFalse(app.otherElements["miniPlayer"].waitForExistence(timeout: 1))
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
        XCTAssertFalse(app.pickerWheels.firstMatch.exists)
        XCTAssertTrue(app.buttons["listening.voice"].waitForExistence(timeout: 3))
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
        let listen = app.buttons["reader.listen"]
        if !waitUntilHittable(listen, timeout: 5) {
            showReaderChrome(in: app)
            if !waitUntilHittable(listen, timeout: 3) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
            }
            XCTAssertTrue(waitUntilHittable(listen, timeout: 5))
        }
        listen.tap()
        return app
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && element.isHittable
    }

    private func waitForValue(of element: XCUIElement, toBe expected: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.value as? String == expected {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func showReaderChrome(in app: XCUIApplication) {
        if app.buttons["reader.listen"].isHittable {
            return
        }
        if app.otherElements["reader.chrome"].exists {
            return
        }
        let hotZone = app.buttons["reader.contentTapArea"]
        if hotZone.waitForExistence(timeout: 1) {
            hotZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }
}
