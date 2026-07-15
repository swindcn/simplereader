import XCTest
import ReadiumShared
@testable import PureVoice

final class SpeechSessionCoordinatorTests: XCTestCase {
    func testOnlyActiveMatchingBookSessionIsReusable() {
        let bookID = UUID()
        let otherBookID = UUID()
        let utterance = SpeechUtterance(
            text: "测试",
            locator: Locator(
                href: AnyURL(string: "EPUB/chapter.xhtml")!,
                mediaType: .xhtml,
                locations: .init(progression: 0.2)
            )
        )

        XCTAssertTrue(SpeechSessionCoordinator.shouldReuseSession(bookID: bookID, existingBookID: bookID, state: .loading))
        XCTAssertTrue(SpeechSessionCoordinator.shouldReuseSession(bookID: bookID, existingBookID: bookID, state: .playing(utterance)))
        XCTAssertTrue(SpeechSessionCoordinator.shouldReuseSession(bookID: bookID, existingBookID: bookID, state: .paused(utterance)))
        XCTAssertFalse(SpeechSessionCoordinator.shouldReuseSession(bookID: bookID, existingBookID: bookID, state: .stopped))
        XCTAssertFalse(SpeechSessionCoordinator.shouldReuseSession(bookID: bookID, existingBookID: bookID, state: .failed("失败")))
        XCTAssertFalse(SpeechSessionCoordinator.shouldReuseSession(bookID: bookID, existingBookID: otherBookID, state: .playing(utterance)))
    }

    @MainActor
    func testFailedFinalProgressFlushIsRetainedForRetry() async {
        let queue = ProgressFinalizationQueue()
        var attempts = 0
        queue.enqueue {
            attempts += 1
            return attempts > 1
        }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(queue.pendingCount, 1)

        queue.retryAll()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(queue.pendingCount, 0)
    }
}
