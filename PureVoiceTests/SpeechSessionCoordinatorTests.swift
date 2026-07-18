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

    @MainActor
    func testEndSessionInvalidatesPendingInterruptionRecovery() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub"))
        let publication = try await PublicationService().open(at: fixture)
        let service = CoordinatorSpeechService()
        let audioSession = CoordinatorControlledAudioSessionActivator()
        let coordinator = SpeechSessionCoordinator(
            repository: InMemoryBookRepository(),
            serviceFactory: { _ in service },
            audioSessionFactory: { audioSession }
        )
        coordinator.begin(book: .fixture(), publication: publication, locator: nil)
        let viewModel = try XCTUnwrap(coordinator.viewModel)
        service.send(.playing(service.utterance))
        viewModel.handleInterruptionBegan()
        service.send(.paused(service.utterance))

        let recovery = Task { await viewModel.handleInterruptionEnded(shouldResume: true) }
        await audioSession.waitUntilActivationStarts()
        coordinator.endSession()
        audioSession.completeSuccessfully()
        await recovery.value

        XCTAssertNil(coordinator.viewModel)
        XCTAssertEqual(service.resumeCount, 0)
    }

    @MainActor
    func testRestorePausedSessionRecreatesListeningWithoutAutoplay() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub"))
        let book = Book.fixture(canonicalFileURL: fixture)
        let position = ReadingPosition(href: "EPUB/chapter.xhtml", progression: 0.2)
        let service = CoordinatorSpeechService()
        let coordinator = SpeechSessionCoordinator(
            repository: InMemoryBookRepository(books: [book]),
            serviceFactory: { _ in service },
            audioSessionFactory: { CoordinatorControlledAudioSessionActivator() }
        )

        await coordinator.restorePausedSession(book: book, position: position)

        let viewModel = try XCTUnwrap(coordinator.viewModel)
        XCTAssertTrue(coordinator.isListeningPresented)
        XCTAssertEqual(viewModel.bookID, book.id)
        XCTAssertEqual(viewModel.currentLocator?.href.string, "EPUB/chapter-1.xhtml")
        XCTAssertEqual(service.startCount, 0)

        viewModel.ensureStarted()
        XCTAssertEqual(service.startCount, 0)

        viewModel.togglePlayback(announces: false)
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(service.startedLocator?.href.string, "EPUB/chapter-1.xhtml")
    }
}

@MainActor
private final class CoordinatorSpeechService: SpeechService {
    var state: SpeechPlaybackState = .stopped
    var onStateChange: ((SpeechPlaybackState) -> Void)?
    let voices: [SpeechVoice] = []
    var rate: Double = 1
    var selectedVoiceIdentifier: String?
    private(set) var resumeCount = 0
    private(set) var startCount = 0
    private(set) var startedLocator: Locator?

    let utterance = SpeechUtterance(
        text: "测试",
        locator: Locator(
            href: AnyURL(string: "EPUB/chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.2)
        )
    )

    func start(from locator: Locator?) {
        startCount += 1
        startedLocator = locator
    }
    func pause() {}
    func resume() { resumeCount += 1 }
    func stop() { send(.stopped) }
    func previous() {}
    func next() {}

    func send(_ state: SpeechPlaybackState) {
        self.state = state
        onStateChange?(state)
    }
}

@MainActor
private final class CoordinatorControlledAudioSessionActivator: AudioSessionActivating {
    private var activationContinuation: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func activate() async throws {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await withCheckedThrowingContinuation { continuation in
            activationContinuation = continuation
        }
    }

    func waitUntilActivationStarts() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func completeSuccessfully() {
        activationContinuation?.resume()
        activationContinuation = nil
    }
}
