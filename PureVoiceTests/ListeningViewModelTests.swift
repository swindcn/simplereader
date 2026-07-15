import AVFoundation
import ReadiumShared
import XCTest
@testable import PureVoice

@MainActor
final class ListeningViewModelTests: XCTestCase {
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ListeningViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartsFromReaderLocatorAndFollowsServiceState() {
        let locator = makeLocator(progression: 0.42)
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, locator: locator)

        viewModel.ensureStarted()
        XCTAssertEqual(service.startedLocators, [locator])
        XCTAssertEqual(viewModel.state, .loading)

        service.send(.playing(.init(text: "当前句", locator: locator)))
        XCTAssertEqual(viewModel.state, .playing(.init(text: "当前句", locator: locator)))
        XCTAssertEqual(viewModel.currentSentence, "当前句")
        XCTAssertTrue(viewModel.isMiniPlayerVisible)

        service.send(.paused(.init(text: "当前句", locator: locator)))
        XCTAssertTrue(viewModel.isMiniPlayerVisible)
        service.send(.stopped)
        XCTAssertFalse(viewModel.isMiniPlayerVisible)
        service.send(.failed("无法合成语音"))
        XCTAssertEqual(viewModel.errorMessage, "无法合成语音")
    }

    func testPlaybackAndSentenceActionsMapExactlyOnceAndAnnounceOnce() {
        let service = FakeSpeechService()
        var announcements: [String] = []
        let viewModel = makeViewModel(service: service, announcements: { announcements.append($0) })

        viewModel.ensureStarted()
        service.send(.playing(service.utterance))
        viewModel.pause()
        service.send(.paused(service.utterance))
        service.send(.paused(service.utterance))
        viewModel.resume()
        service.send(.playing(service.utterance))
        viewModel.previousSentence()
        viewModel.nextSentence()

        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(service.pauseCount, 1)
        XCTAssertEqual(service.resumeCount, 1)
        XCTAssertEqual(service.previousCount, 1)
        XCTAssertEqual(service.nextCount, 1)
        XCTAssertEqual(announcements, ["开始播放", "已暂停", "继续播放", "上一句", "下一句"])
    }

    func testEnsureStartedDoesNotResumeOrAnnounceWhenPausedSessionReappears() {
        let service = FakeSpeechService()
        var announcements: [String] = []
        let viewModel = makeViewModel(service: service, announcements: { announcements.append($0) })

        viewModel.ensureStarted()
        service.send(.playing(service.utterance))
        viewModel.pause()
        service.send(.paused(service.utterance))
        let announcementsBeforeReappearing = announcements

        viewModel.ensureStarted()

        XCTAssertEqual(viewModel.state, .paused(service.utterance))
        XCTAssertEqual(service.startCount, 1)
        XCTAssertEqual(service.resumeCount, 0)
        XCTAssertEqual(announcements, announcementsBeforeReappearing)
    }

    func testEnsureStartedIsNoOpForOtherExistingSessionStates() {
        for existingState in [
            SpeechPlaybackState.loading,
            .playing(FakeSpeechService().utterance),
            .stopped
        ] {
            let service = FakeSpeechService()
            var announcements: [String] = []
            let viewModel = makeViewModel(service: service, announcements: { announcements.append($0) })
            viewModel.ensureStarted()
            service.send(existingState)
            let announcementsBeforeReappearing = announcements

            viewModel.ensureStarted()

            XCTAssertEqual(viewModel.state, existingState)
            XCTAssertEqual(service.startCount, 1)
            XCTAssertEqual(service.resumeCount, 0)
            XCTAssertEqual(announcements, announcementsBeforeReappearing)
        }
    }

    func testRateClampsAppliesAndPersistsSemanticMultiplier() {
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service)

        viewModel.setRate(3)
        XCTAssertEqual(viewModel.rate, 2)
        XCTAssertEqual(service.rate, 2)
        viewModel.setRate(0.2)
        XCTAssertEqual(viewModel.rate, 0.5)
        XCTAssertEqual(service.rate, 0.5)
        viewModel.setRate(1.25)

        let restoredService = FakeSpeechService()
        let restored = makeViewModel(service: restoredService)
        XCTAssertEqual(restored.rate, 1.25)
        XCTAssertEqual(restoredService.rate, 1.25)
    }

    func testVoiceIdentifierPersistsAndUnavailableVoiceFallsBackWithoutInventingGender() {
        let voices = [
            SpeechVoice(identifier: "zh-female", name: "Mei", language: "zh-CN", gender: .female, quality: .high),
            SpeechVoice(identifier: "zh-unknown", name: "Ting", language: "zh-CN", gender: .unspecified, quality: .medium)
        ]
        let service = FakeSpeechService(voices: voices)
        let viewModel = makeViewModel(service: service)

        viewModel.selectVoice(identifier: "zh-unknown")
        XCTAssertEqual(service.selectedVoiceIdentifier, "zh-unknown")
        XCTAssertEqual(voices[1].genderLabel, "未指定")

        let restoredService = FakeSpeechService(voices: voices)
        _ = makeViewModel(service: restoredService)
        XCTAssertEqual(restoredService.selectedVoiceIdentifier, "zh-unknown")

        let fallbackService = FakeSpeechService(voices: [voices[0]])
        let fallback = makeViewModel(service: fallbackService)
        XCTAssertEqual(fallback.selectedVoiceIdentifier, "zh-female")
        XCTAssertEqual(fallbackService.selectedVoiceIdentifier, "zh-female")
    }

    func testInterruptionOnlyResumesWhenAllowedAndWasPlaying() {
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service)
        service.send(.playing(service.utterance))

        viewModel.handleInterruptionBegan()
        XCTAssertEqual(service.pauseCount, 1)
        viewModel.handleInterruptionEnded(shouldResume: false)
        XCTAssertEqual(service.resumeCount, 0)

        service.send(.playing(service.utterance))
        viewModel.handleInterruptionBegan()
        viewModel.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(service.resumeCount, 1)

        service.send(.paused(service.utterance))
        viewModel.handleInterruptionBegan()
        viewModel.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(service.resumeCount, 1)
    }

    func testFlushPersistsCurrentSpeechLocatorWithAtomicPositionUpdate() async throws {
        let repository = RecordingPositionRepository()
        let locator = makeLocator(progression: 0.63)
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, repository: repository)
        service.send(.playing(.init(text: "保存这一句", locator: locator)))

        let succeeded = await viewModel.flushProgress()

        XCTAssertTrue(succeeded)
        let snapshot = await repository.snapshot()
        let update = try XCTUnwrap(snapshot.updates.first)
        XCTAssertEqual(update.id, viewModel.bookID)
        XCTAssertEqual(update.position?.href, locator.href.string)
        XCTAssertEqual(update.position?.progression, 0.63)
        XCTAssertEqual(snapshot.fullSaveCount, 0)
    }

    func testFailedPositionPersistenceIsReportedAndRetainedForRetry() async {
        let repository = RecordingPositionRepository(shouldFail: true)
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, repository: repository)
        service.send(.playing(service.utterance))

        let failed = await viewModel.flushProgress()
        XCTAssertFalse(failed)
        XCTAssertEqual(viewModel.errorMessage, "无法保存听书进度。")

        await repository.setShouldFail(false)
        let succeeded = await viewModel.flushProgress()
        let snapshot = await repository.snapshot()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(snapshot.updates.count, 1)
    }

    func testReadiumRateMappingUsesSemanticMultiplierInsteadOfRawAVRate() {
        XCTAssertEqual(ReadiumSpeechService.avSpeechRate(for: 0.5), Double(AVSpeechUtteranceMinimumSpeechRate))
        XCTAssertEqual(ReadiumSpeechService.avSpeechRate(for: 1), Double(AVSpeechUtteranceDefaultSpeechRate))
        XCTAssertEqual(ReadiumSpeechService.avSpeechRate(for: 2), Double(AVSpeechUtteranceMaximumSpeechRate))
    }

    func testReadiumVoiceOrderingPrefersPublicationLanguageThenQualityAndStableName() {
        let voices = [
            SpeechVoice(identifier: "en", name: "Alex", language: "en-US", gender: .male, quality: .higher),
            SpeechVoice(identifier: "zh-low", name: "Yu", language: "zh-TW", gender: .male, quality: .low),
            SpeechVoice(identifier: "zh-z", name: "Zhi", language: "zh-CN", gender: .female, quality: .high),
            SpeechVoice(identifier: "zh-a", name: "An", language: "zh-CN", gender: .female, quality: .high)
        ]

        let ordered = ReadiumSpeechService.orderedVoices(voices, preferredLanguage: "zh-CN")

        XCTAssertEqual(ordered.map(\.identifier), ["zh-a", "zh-z", "zh-low"])
        XCTAssertTrue(ReadiumSpeechService.orderedVoices([voices[0]], preferredLanguage: "zh-CN").isEmpty)
    }

    func testReadiumServiceWrapsSpeakablePublicationAndExposesCompatibleDeviceVoices() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub"))
        let publication = try await PublicationService().open(at: fixture)

        let service = try XCTUnwrap(ReadiumSpeechService(publication: publication))

        XCTAssertTrue(service.voices.allSatisfy {
            $0.language.lowercased().hasPrefix("zh")
        })
    }

    private func makeViewModel(
        service: FakeSpeechService,
        locator: Locator? = nil,
        repository: any BookRepository = InMemoryBookRepository(),
        announcements: @escaping (String) -> Void = { _ in }
    ) -> ListeningViewModel {
        ListeningViewModel(
            book: .fixture(title: "测试书", author: "测试作者"),
            publication: nil,
            initialLocator: locator,
            repository: repository,
            service: service,
            defaults: defaults,
            announce: announcements,
            observesAudioSession: false
        )
    }

    private func makeLocator(progression: Double = 0.25) -> Locator {
        Locator(
            href: AnyURL(string: "EPUB/chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: progression, totalProgression: progression)
        )
    }
}

@MainActor
private final class FakeSpeechService: SpeechService {
    var state: SpeechPlaybackState = .stopped
    var onStateChange: ((SpeechPlaybackState) -> Void)?
    let voices: [SpeechVoice]
    var rate: Double = 1
    var selectedVoiceIdentifier: String?

    private(set) var startedLocators: [Locator?] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var previousCount = 0
    private(set) var nextCount = 0
    var startCount: Int { startedLocators.count }

    let utterance = SpeechUtterance(
        text: "测试句子",
        locator: Locator(
            href: AnyURL(string: "EPUB/chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.2, totalProgression: 0.2)
        )
    )

    init(voices: [SpeechVoice] = []) {
        self.voices = voices
    }

    func start(from locator: Locator?) { startedLocators.append(locator) }
    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
    func stop() { stopCount += 1 }
    func previous() { previousCount += 1 }
    func next() { nextCount += 1 }

    func send(_ state: SpeechPlaybackState) {
        self.state = state
        onStateChange?(state)
    }
}

private actor RecordingPositionRepository: BookRepository {
    struct Update: Sendable {
        let id: UUID
        let position: ReadingPosition?
    }

    private(set) var updates: [Update] = []
    private(set) var fullSaveCount = 0
    private var shouldFail: Bool

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func setShouldFail(_ value: Bool) { shouldFail = value }
    func snapshot() -> (updates: [Update], fullSaveCount: Int) { (updates, fullSaveCount) }
    func allBooks() -> [Book] { [] }
    func recentBooks(limit: Int) -> [Book] { [] }
    func book(id: UUID) -> Book? { nil }
    func save(_ book: Book) { fullSaveCount += 1 }
    func updatePosition(id: UUID, position: ReadingPosition?) throws {
        if shouldFail { throw TestError.failed }
        updates.append(.init(id: id, position: position))
    }
    func delete(id: UUID) {}

    private enum TestError: Error { case failed }
}
