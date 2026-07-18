import XCTest
@testable import PureVoice

final class AppStateRestorerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppStateRestorerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInterruptedImportConversionBecomesFailedRecoveryPlanAndPreservesOriginal() throws {
        let restorer = AppStateRestorer(defaults: defaults)
        let bookID = UUID()
        let originalURL = URL(fileURLWithPath: "/tmp/\(bookID.uuidString)/original.txt")

        restorer.recordImport(bookID: bookID, originalFileURL: originalURL, state: .converting(.txt))

        let restored = AppStateRestorer(defaults: defaults)
        let plan = try XCTUnwrap(restored.restoreLaunchState())

        XCTAssertEqual(
            plan,
            .markImportFailed(
                bookID: bookID,
                originalFileURL: originalURL,
                error: UserFacingError.importInterrupted
            )
        )
        XCTAssertNil(restored.restoreLaunchState())
    }

    func testCompletedImportClearsPendingImportState() {
        let restorer = AppStateRestorer(defaults: defaults)
        let bookID = UUID()
        restorer.recordImport(
            bookID: bookID,
            originalFileURL: URL(fileURLWithPath: "/tmp/\(bookID.uuidString)/original.txt"),
            state: .copying
        )

        restorer.recordImport(bookID: bookID, originalFileURL: nil, state: .completed(bookID))

        XCTAssertNil(AppStateRestorer(defaults: defaults).restoreLaunchState())
    }

    func testReadingAndListeningPositionsRestoreSafeWorkWithoutAutoplay() throws {
        let restorer = AppStateRestorer(defaults: defaults)
        let readingBookID = UUID()
        let listeningBookID = UUID()
        let readingPosition = ReadingPosition(href: "chapter-1.xhtml", progression: 0.35)
        let listeningPosition = ReadingPosition(href: "chapter-2.xhtml", progression: 0.72)

        restorer.recordReading(bookID: readingBookID, position: readingPosition)
        XCTAssertEqual(
            AppStateRestorer(defaults: defaults).restoreLaunchState(),
            .reopenReader(bookID: readingBookID, position: readingPosition)
        )

        restorer.recordListening(bookID: listeningBookID, position: listeningPosition, wasPlaying: true)
        XCTAssertEqual(
            AppStateRestorer(defaults: defaults).restoreLaunchState(),
            .reopenListening(bookID: listeningBookID, position: listeningPosition, shouldAutoplay: false)
        )
    }
}
