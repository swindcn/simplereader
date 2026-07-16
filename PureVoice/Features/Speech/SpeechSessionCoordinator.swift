import Foundation
@preconcurrency import ReadiumShared

@MainActor
final class SpeechSessionCoordinator: ObservableObject {
    @Published private(set) var viewModel: ListeningViewModel?
    @Published var isListeningPresented = false
    @Published var errorMessage: String?

    private let repository: any BookRepository
    private let preferencesStore: PreferencesStore
    private let serviceFactory: @MainActor (OpenedPublication) -> (any SpeechService)?
    private let audioSessionFactory: @MainActor () -> any AudioSessionActivating
    private let finalizations = ProgressFinalizationQueue()
    private var remoteCommands: RemoteCommandController?

    var hasPendingProgressRetry: Bool { finalizations.pendingCount > 0 }

    init(
        repository: any BookRepository,
        preferencesStore: PreferencesStore? = nil,
        serviceFactory: @MainActor @escaping (OpenedPublication) -> (any SpeechService)? = SpeechSessionCoordinator.makeService,
        audioSessionFactory: @MainActor @escaping () -> any AudioSessionActivating = { SystemAudioSessionActivator() }
    ) {
        self.repository = repository
        self.preferencesStore = preferencesStore ?? PreferencesStore()
        self.serviceFactory = serviceFactory
        self.audioSessionFactory = audioSessionFactory
        finalizations.onFailure = { [weak self] in
            self?.errorMessage = "无法保存听书进度，请重试。"
        }
    }

    func begin(book: Book, publication: OpenedPublication, locator: Locator?) {
        if let viewModel, Self.shouldReuseSession(
            bookID: book.id,
            existingBookID: viewModel.bookID,
            state: viewModel.state
        ) {
            isListeningPresented = true
            return
        }
        endSession()

        let service = serviceFactory(publication)
        guard let service else {
            errorMessage = "这本书暂不支持听书。"
            return
        }

        let viewModel = ListeningViewModel(
            book: book,
            publication: publication,
            initialLocator: locator,
            repository: repository,
            service: service,
            preferencesStore: preferencesStore,
            audioSession: audioSessionFactory()
        )
        let remoteCommands = RemoteCommandController { [weak viewModel] command in
            guard let viewModel else { return }
            switch command {
            case .play: viewModel.resume(announces: false)
            case .pause: viewModel.pause(announces: false)
            case .toggle: viewModel.togglePlayback(announces: false)
            case .next: viewModel.nextSentence(announces: false)
            case .previous: viewModel.previousSentence(announces: false)
            }
        }
        viewModel.onNowPlayingChange = { [weak viewModel] in
            guard let viewModel else { return }
            remoteCommands.update(
                state: viewModel.state,
                metadata: .init(
                    title: viewModel.title,
                    author: viewModel.author,
                    rate: viewModel.rate,
                    isPlaying: viewModel.state.isPlaying
                )
            )
        }
        self.remoteCommands = remoteCommands
        self.viewModel = viewModel
        isListeningPresented = true
    }

    func dismissListening(flushesProgress: Bool = true) {
        isListeningPresented = false
        if flushesProgress {
            Task { await viewModel?.flushProgress() }
        }
    }

    func presentListening() {
        guard viewModel?.isMiniPlayerVisible == true else { return }
        isListeningPresented = true
    }

    func endSession() {
        let endingViewModel = viewModel
        endingViewModel?.teardown()
        if let endingViewModel {
            finalizations.enqueue {
                await endingViewModel.flushProgress()
            }
        }
        remoteCommands?.teardown()
        remoteCommands = nil
        viewModel = nil
        isListeningPresented = false
    }

    @discardableResult
    func flushProgress() async -> Bool {
        await viewModel?.flushProgress() ?? true
    }

    nonisolated static func shouldReuseSession(
        bookID: UUID,
        existingBookID: UUID,
        state: SpeechPlaybackState
    ) -> Bool {
        guard bookID == existingBookID else { return false }
        switch state {
        case .loading, .playing, .paused:
            return true
        case .stopped, .failed:
            return false
        }
    }

    func dismissError() { errorMessage = nil }

    func retryPendingProgress() {
        errorMessage = nil
        finalizations.retryAll()
    }

    private static func makeService(publication: OpenedPublication) -> (any SpeechService)? {
#if DEBUG
        if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_LISTENING"] == "1" {
            return DebugSpeechService()
        }
#endif
        return ReadiumSpeechService(publication: publication)
    }
}

@MainActor
final class ProgressFinalizationQueue {
    typealias Operation = @MainActor () async -> Bool

    var onFailure: (() -> Void)?
    var pendingCount: Int { operations.count }

    private var operations: [UUID: Operation] = [:]
    private var running: Set<UUID> = []

    func enqueue(_ operation: @escaping Operation) {
        let id = UUID()
        operations[id] = operation
        run(id)
    }

    func retryAll() {
        for id in operations.keys {
            run(id)
        }
    }

    private func run(_ id: UUID) {
        guard let operation = operations[id], !running.contains(id) else { return }
        running.insert(id)
        Task {
            let succeeded = await operation()
            running.remove(id)
            if succeeded {
                operations.removeValue(forKey: id)
            } else {
                onFailure?()
            }
        }
    }
}

#if DEBUG
@MainActor
private final class DebugSpeechService: SpeechService {
    private(set) var state: SpeechPlaybackState = .stopped
    var onStateChange: ((SpeechPlaybackState) -> Void)?
    let voices = [
        SpeechVoice(identifier: "debug-female", name: "小语", language: "zh-CN", gender: .female, quality: .high),
        SpeechVoice(identifier: "debug-male", name: "小宇", language: "zh-CN", gender: .male, quality: .medium)
    ]
    var rate: Double = 1
    var selectedVoiceIdentifier: String?

    private var locator: Locator?
    private var sentenceIndex = 0

    func start(from locator: Locator?) {
        self.locator = locator ?? makeLocator(progression: 0.1)
        publishPlaying()
    }

    func pause() {
        guard let utterance = state.utterance else { return }
        publish(.paused(utterance))
    }

    func resume() { publishPlaying() }
    func stop() { publish(.stopped) }

    func previous() {
        sentenceIndex = max(sentenceIndex - 1, 0)
        locator = makeLocator(progression: Double(sentenceIndex + 1) / 10)
        publishPlaying()
    }

    func next() {
        sentenceIndex += 1
        locator = makeLocator(progression: Double(sentenceIndex + 1) / 10)
        publishPlaying()
    }

    private func publishPlaying() {
        guard let locator else { return }
        publish(.playing(.init(text: "这是第 \(sentenceIndex + 1) 句测试听书内容。", locator: locator)))
    }

    private func publish(_ state: SpeechPlaybackState) {
        self.state = state
        onStateChange?(state)
    }

    private func makeLocator(progression: Double) -> Locator {
        Locator(
            href: AnyURL(string: "EPUB/chapter-1.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: progression, totalProgression: progression)
        )
    }
}
#endif
