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

    func testInterruptionOnlyResumesAfterAudioSessionActivationSucceeds() async {
        var events: [String] = []
        let service = FakeSpeechService(onResume: { events.append("resume") })
        let audioSession = FakeAudioSessionActivator(onActivate: { events.append("activate") })
        let viewModel = makeViewModel(service: service, audioSession: audioSession)
        service.send(.playing(service.utterance))

        viewModel.handleInterruptionBegan()
        XCTAssertEqual(service.pauseCount, 1)
        await viewModel.handleInterruptionEnded(shouldResume: false)
        XCTAssertEqual(service.resumeCount, 0)

        service.send(.playing(service.utterance))
        viewModel.handleInterruptionBegan()
        await viewModel.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(audioSession.activationCount, 1)
        XCTAssertEqual(service.resumeCount, 1)
        XCTAssertEqual(events, ["activate", "resume"])

        service.send(.paused(service.utterance))
        viewModel.handleInterruptionBegan()
        await viewModel.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(service.resumeCount, 1)
    }

    func testInterruptionActivationFailureDoesNotResumeAndReportsRecoverableError() async {
        let service = FakeSpeechService()
        let audioSession = FakeAudioSessionActivator(shouldFail: true)
        let viewModel = makeViewModel(service: service, audioSession: audioSession)
        service.send(.playing(service.utterance))

        viewModel.handleInterruptionBegan()
        await viewModel.handleInterruptionEnded(shouldResume: true)

        XCTAssertEqual(audioSession.activationCount, 1)
        XCTAssertEqual(service.resumeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "无法恢复播放，请点击播放重试。")
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

    func testSavedLocatorRemainsAvailableForReaderAfterStoppedOrFailed() async {
        let locator = makeLocator(progression: 0.71)
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service)
        service.send(.playing(.init(text: "最后一句", locator: locator)))

        _ = await viewModel.flushProgress()
        service.send(.stopped)
        XCTAssertEqual(viewModel.currentLocator, locator)
        service.send(.failed("语音失败"))
        XCTAssertEqual(viewModel.currentLocator, locator)
    }

    func testLatestLocatorPersistsAutomaticallyAfterDebounce() async throws {
        let repository = RecordingPositionRepository()
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, repository: repository, persistenceDelay: 0.02)
        service.send(.playing(.init(text: "第一句", locator: makeLocator(progression: 0.2))))
        service.send(.playing(.init(text: "第二句", locator: makeLocator(progression: 0.8))))

        try await Task.sleep(nanoseconds: 80_000_000)

        let snapshot = await repository.snapshot()
        XCTAssertEqual(snapshot.updates.map(\.position?.progression), [0.8])
    }

    func testNaturalStopFlushesImmediately() async {
        let repository = RecordingPositionRepository()
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, repository: repository, persistenceDelay: 60)
        service.send(.playing(.init(text: "最后一句", locator: makeLocator(progression: 0.9))))

        service.send(.stopped)
        for _ in 0..<30 { await Task.yield() }

        let snapshot = await repository.snapshot()
        XCTAssertEqual(snapshot.updates.map(\.position?.progression), [0.9])
    }

    func testConcurrentFlushSerializesAndDrainsLatestLocator() async {
        let repository = ControlledPositionRepository(outcomes: [.success, .success])
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, repository: repository, persistenceDelay: 60)
        service.send(.playing(.init(text: "旧", locator: makeLocator(progression: 0.2))))
        let firstFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(1)

        service.send(.playing(.init(text: "新", locator: makeLocator(progression: 0.85))))
        let joinedFlush = Task { await viewModel.flushProgress() }
        for _ in 0..<20 { await Task.yield() }
        let startsWhileBlocked = await repository.startedCount
        let concurrencyWhileBlocked = await repository.maximumConcurrentSaveCount
        XCTAssertEqual(startsWhileBlocked, 1)
        XCTAssertEqual(concurrencyWhileBlocked, 1)

        await repository.releaseNextSave()
        await repository.waitUntilSaveStarts(2)
        await repository.releaseNextSave()
        let firstOutcome = await firstFlush.value
        let joinedOutcome = await joinedFlush.value
        let savedProgressions = await repository.savedProgressions
        let maximumConcurrency = await repository.maximumConcurrentSaveCount
        XCTAssertTrue(firstOutcome)
        XCTAssertTrue(joinedOutcome)
        XCTAssertEqual(savedProgressions, [0.2, 0.85])
        XCTAssertEqual(maximumConcurrency, 1)
    }

    func testFailedOldSaveRetainsLatestLocatorForRetry() async {
        let repository = ControlledPositionRepository(outcomes: [.failure, .success])
        let service = FakeSpeechService()
        let viewModel = makeViewModel(service: service, repository: repository, persistenceDelay: 60)
        service.send(.playing(.init(text: "旧", locator: makeLocator(progression: 0.25))))
        let failedFlush = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(1)
        service.send(.playing(.init(text: "新", locator: makeLocator(progression: 0.95))))
        await repository.releaseNextSave()
        let failedOutcome = await failedFlush.value
        XCTAssertFalse(failedOutcome)

        let retry = Task { await viewModel.flushProgress() }
        await repository.waitUntilSaveStarts(2)
        await repository.releaseNextSave()
        let retryOutcome = await retry.value
        let attemptedProgressions = await repository.attemptedProgressions
        let savedProgressions = await repository.savedProgressions
        XCTAssertTrue(retryOutcome)
        XCTAssertEqual(attemptedProgressions, [0.25, 0.95])
        XCTAssertEqual(savedProgressions, [0.95])
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
        let defaultRate = Double(AVSpeechUtteranceDefaultSpeechRate)
        let minimum = Double(AVSpeechUtteranceMinimumSpeechRate)
        let maximum = Double(AVSpeechUtteranceMaximumSpeechRate)
        XCTAssertEqual(ReadiumSpeechService.avSpeechRate(for: 0.5), min(max(defaultRate * 0.5, minimum), maximum))
        XCTAssertEqual(ReadiumSpeechService.avSpeechRate(for: 1), Double(AVSpeechUtteranceDefaultSpeechRate))
        XCTAssertEqual(ReadiumSpeechService.avSpeechRate(for: 2), min(max(defaultRate * 2, minimum), maximum))
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
        XCTAssertEqual(
            ReadiumSpeechService.orderedVoices([voices[0]], preferredLanguage: "zh-CN").map(\.identifier),
            ["en"]
        )
    }

    func testNativeAdjustableSettingBindingsDoNotPostCustomAnnouncements() {
        let voices = [SpeechVoice(identifier: "voice", name: "Mei", language: "zh-CN", gender: .female, quality: .high)]
        let service = FakeSpeechService(voices: voices)
        var announcements: [String] = []
        let viewModel = makeViewModel(service: service, announcements: { announcements.append($0) })

        viewModel.setRate(1.5, announces: false)
        viewModel.selectVoice(identifier: "voice", announces: false)

        XCTAssertTrue(announcements.isEmpty)
        XCTAssertEqual(viewModel.rate, 1.5)
        XCTAssertEqual(viewModel.selectedVoiceIdentifier, "voice")
    }

    func testReadiumServiceWrapsSpeakablePublicationAndExposesDeviceVoiceFallback() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "minimal", withExtension: "epub"))
        let publication = try await PublicationService().open(at: fixture)

        let service = try XCTUnwrap(ReadiumSpeechService(publication: publication))

        XCTAssertFalse(service.voices.isEmpty)
    }

    private func makeViewModel(
        service: FakeSpeechService,
        locator: Locator? = nil,
        repository: any BookRepository = InMemoryBookRepository(),
        announcements: @escaping (String) -> Void = { _ in },
        persistenceDelay: TimeInterval = 60,
        audioSession: any AudioSessionActivating = FakeAudioSessionActivator()
    ) -> ListeningViewModel {
        ListeningViewModel(
            book: .fixture(title: "测试书", author: "测试作者"),
            publication: nil,
            initialLocator: locator,
            repository: repository,
            service: service,
            defaults: defaults,
            announce: announcements,
            observesAudioSession: false,
            persistenceDelay: persistenceDelay,
            audioSession: audioSession
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
    private let onResume: () -> Void

    let utterance = SpeechUtterance(
        text: "测试句子",
        locator: Locator(
            href: AnyURL(string: "EPUB/chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.2, totalProgression: 0.2)
        )
    )

    init(voices: [SpeechVoice] = [], onResume: @escaping () -> Void = {}) {
        self.voices = voices
        self.onResume = onResume
    }

    func start(from locator: Locator?) { startedLocators.append(locator) }
    func pause() { pauseCount += 1 }
    func resume() {
        resumeCount += 1
        onResume()
    }
    func stop() { stopCount += 1 }
    func previous() { previousCount += 1 }
    func next() { nextCount += 1 }

    func send(_ state: SpeechPlaybackState) {
        self.state = state
        onStateChange?(state)
    }
}

@MainActor
private final class FakeAudioSessionActivator: AudioSessionActivating {
    private(set) var activationCount = 0
    private let shouldFail: Bool
    private let onActivate: () -> Void

    init(shouldFail: Bool = false, onActivate: @escaping () -> Void = {}) {
        self.shouldFail = shouldFail
        self.onActivate = onActivate
    }

    func activate() async throws {
        activationCount += 1
        onActivate()
        if shouldFail { throw ActivationError.expected }
    }

    private enum ActivationError: Error { case expected }
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

private actor ControlledPositionRepository: BookRepository {
    enum Outcome { case success, failure }

    private var outcomes: [Outcome]
    private var attempted: [Double] = []
    private var saved: [Double] = []
    private var activeSaveCount = 0
    private(set) var maximumConcurrentSaveCount = 0
    private var saveContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    var startedCount: Int { attempted.count }
    var attemptedProgressions: [Double] { attempted }
    var savedProgressions: [Double] { saved }

    func allBooks() -> [Book] { [] }
    func recentBooks(limit: Int) -> [Book] { [] }
    func book(id: UUID) -> Book? { nil }
    func save(_ book: Book) {}

    func updatePosition(id: UUID, position: ReadingPosition?) async throws {
        let progression = position?.progression ?? 0
        attempted.append(progression)
        activeSaveCount += 1
        maximumConcurrentSaveCount = max(maximumConcurrentSaveCount, activeSaveCount)
        resumeSatisfiedStartWaiters()

        await withCheckedContinuation { continuation in
            saveContinuations.append(continuation)
        }

        activeSaveCount -= 1
        let outcome = outcomes.isEmpty ? Outcome.success : outcomes.removeFirst()
        switch outcome {
        case .success:
            saved.append(progression)
        case .failure:
            throw ControlledSaveError.expected
        }
    }

    func delete(id: UUID) {}

    func waitUntilSaveStarts(_ count: Int) async {
        guard attempted.count < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func releaseNextSave() {
        guard !saveContinuations.isEmpty else { return }
        saveContinuations.removeFirst().resume()
    }

    private func resumeSatisfiedStartWaiters() {
        let satisfied = startWaiters.filter { attempted.count >= $0.count }
        startWaiters.removeAll { attempted.count >= $0.count }
        satisfied.forEach { $0.continuation.resume() }
    }

    private enum ControlledSaveError: Error { case expected }
}
