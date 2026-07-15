import Foundation
@preconcurrency import ReadiumShared

@MainActor
final class SpeechSessionCoordinator: ObservableObject {
    @Published private(set) var viewModel: ListeningViewModel?
    @Published var isListeningPresented = false
    @Published var errorMessage: String?

    private let repository: any BookRepository
    private var remoteCommands: RemoteCommandController?

    init(repository: any BookRepository) {
        self.repository = repository
    }

    func begin(book: Book, publication: OpenedPublication, locator: Locator?) {
        if let viewModel, viewModel.bookID == book.id {
            isListeningPresented = true
            return
        }
        endSession()

        let service: (any SpeechService)?
#if DEBUG
        if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_LISTENING"] == "1" {
            service = DebugSpeechService()
        } else {
            service = ReadiumSpeechService(publication: publication)
        }
#else
        service = ReadiumSpeechService(publication: publication)
#endif
        guard let service else {
            errorMessage = "这本书暂不支持听书。"
            return
        }

        let viewModel = ListeningViewModel(
            book: book,
            publication: publication,
            initialLocator: locator,
            repository: repository,
            service: service
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

    func dismissListening() {
        isListeningPresented = false
        Task { await viewModel?.flushProgress() }
    }

    func presentListening() {
        guard viewModel?.isMiniPlayerVisible == true else { return }
        isListeningPresented = true
    }

    func endSession() {
        viewModel?.stop(announces: false)
        viewModel?.onNowPlayingChange = nil
        remoteCommands?.teardown()
        remoteCommands = nil
        viewModel = nil
        isListeningPresented = false
    }

    func dismissError() { errorMessage = nil }
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
