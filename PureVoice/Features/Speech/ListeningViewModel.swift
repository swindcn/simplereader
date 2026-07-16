import AVFoundation
import Foundation
import UIKit
@preconcurrency import ReadiumShared

@MainActor
final class ListeningViewModel: NSObject, ObservableObject {
    @Published private(set) var state: SpeechPlaybackState = .stopped
    @Published private(set) var rate: Double
    @Published private(set) var selectedVoiceIdentifier: String?
    @Published private(set) var errorMessage: String?
    var onNowPlayingChange: (() -> Void)?

    let bookID: UUID
    let title: String
    let author: String
    let coverURL: URL?
    let voices: [SpeechVoice]

    var currentSentence: String { state.utterance?.text ?? "等待播放" }
    var currentLocator: Locator? { lastKnownLocator ?? initialLocator }
    var isMiniPlayerVisible: Bool {
        switch state {
        case .playing, .paused: true
        case .loading, .stopped, .failed: false
        }
    }

    private static let rateKey = "speech.rateMultiplier"
    private static let voiceKey = "speech.voiceIdentifier"
    private let publication: OpenedPublication?
    private let initialLocator: Locator?
    private let repository: any BookRepository
    private let service: any SpeechService
    private let defaults: UserDefaults
    private let announce: (String) -> Void
    private let persistenceDelay: TimeInterval
    private let audioSession: any AudioSessionActivating
    private var lastKnownLocator: Locator?
    private var pendingLocator: Locator?
    private var persistenceTask: Task<Void, Never>?
    private var isPersisting = false
    private var persistenceWaiters: [CheckedContinuation<Bool, Never>] = []
    private var wasPlayingBeforeInterruption = false
    private var interruptionGeneration = 0
    private var hasStarted = false

    init(
        book: Book,
        publication: OpenedPublication?,
        initialLocator: Locator?,
        repository: any BookRepository,
        service: any SpeechService,
        defaults: UserDefaults = .standard,
        announce: @escaping (String) -> Void = { message in
            UIAccessibility.post(notification: .announcement, argument: message)
        },
        observesAudioSession: Bool = true,
        persistenceDelay: TimeInterval = 1,
        audioSession: any AudioSessionActivating = SystemAudioSessionActivator()
    ) {
        bookID = book.id
        title = book.title
        author = book.author
        coverURL = book.coverFileURL ?? publication?.coverURL
        self.publication = publication
        self.initialLocator = initialLocator
        self.repository = repository
        self.service = service
        self.defaults = defaults
        self.announce = announce
        self.persistenceDelay = persistenceDelay
        self.audioSession = audioSession
        lastKnownLocator = initialLocator
        voices = service.voices

        let persistedRate = defaults.object(forKey: Self.rateKey) as? Double ?? 1
        let restoredRate = Self.clampedRate(persistedRate)
        rate = restoredRate
        service.rate = restoredRate

        let savedVoice = defaults.string(forKey: Self.voiceKey)
        let restoredVoice = voices.first { $0.identifier == savedVoice } ?? voices.first
        selectedVoiceIdentifier = restoredVoice?.identifier
        service.selectedVoiceIdentifier = restoredVoice?.identifier
        if let restoredVoice { defaults.set(restoredVoice.identifier, forKey: Self.voiceKey) }

        super.init()
        service.onStateChange = { [weak self] state in
            self?.receive(state)
        }
        if observesAudioSession {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(audioSessionInterrupted(_:)),
                name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(audioRouteChanged(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance()
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func ensureStarted() {
        guard !hasStarted else { return }
        startPlayback(from: initialLocator, announces: true)
    }

    func pause(announces: Bool = true) {
        invalidateInterruptionRecovery()
        service.pause()
        if announces { announce("已暂停") }
    }

    func resume(announces: Bool = true) {
        invalidateInterruptionRecovery()
        service.resume()
        if announces { announce("继续播放") }
    }

    func togglePlayback(announces: Bool = true) {
        switch state {
        case .playing:
            pause(announces: announces)
        case .paused:
            resume(announces: announces)
        case .stopped, .failed:
            hasStarted = false
            startPlayback(from: pendingLocator ?? initialLocator, announces: announces)
        case .loading:
            break
        }
    }

    func stop(announces: Bool = true) {
        invalidateInterruptionRecovery()
        service.stop()
        if announces { announce("已停止") }
        Task { await flushProgress() }
    }

    func teardown() {
        stop(announces: false)
        onNowPlayingChange = nil
    }

    func previousSentence(announces: Bool = true) {
        service.previous()
        if announces { announce("上一句") }
    }

    func nextSentence(announces: Bool = true) {
        service.next()
        if announces { announce("下一句") }
    }

    func setRate(_ newValue: Double, announces: Bool = true) {
        let clamped = Self.clampedRate(newValue)
        rate = clamped
        service.rate = clamped
        defaults.set(clamped, forKey: Self.rateKey)
        if announces { announce("语速 \(Self.rateLabel(clamped))") }
        onNowPlayingChange?()
    }

    func selectVoice(identifier: String, announces: Bool = true) {
        guard voices.contains(where: { $0.identifier == identifier }) else { return }
        selectedVoiceIdentifier = identifier
        service.selectedVoiceIdentifier = identifier
        defaults.set(identifier, forKey: Self.voiceKey)
        if announces, let voice = voices.first(where: { $0.identifier == identifier }) {
            announce("已选择\(voice.displayName)")
        }
    }

    func dismissError() { errorMessage = nil }

    func handleInterruptionBegan() {
        invalidateInterruptionRecovery()
        wasPlayingBeforeInterruption = state.isPlaying
        if wasPlayingBeforeInterruption { service.pause() }
    }

    func handleInterruptionEnded(shouldResume: Bool) async {
        let generation = interruptionGeneration
        await completeInterruptionRecovery(shouldResume: shouldResume, generation: generation)
    }

    private func completeInterruptionRecovery(shouldResume: Bool, generation: Int) async {
        guard shouldResume, isInterruptionRecoveryCurrent(generation: generation) else {
            if generation == interruptionGeneration { invalidateInterruptionRecovery() }
            return
        }
        do {
            try await audioSession.activate()
        } catch {
            guard canCompleteInterruptionRecovery(generation: generation) else { return }
            errorMessage = "无法恢复播放，请点击播放重试。"
            invalidateInterruptionRecovery()
            return
        }
        guard canCompleteInterruptionRecovery(generation: generation) else { return }
        invalidateInterruptionRecovery()
        service.resume()
    }

    @discardableResult
    func flushProgress() async -> Bool {
        persistenceTask?.cancel()
        persistenceTask = nil

        if isPersisting {
            return await withCheckedContinuation { continuation in
                persistenceWaiters.append(continuation)
            }
        }

        guard pendingLocator != nil else { return true }
        isPersisting = true
        let succeeded = await drainPendingProgress()
        isPersisting = false

        let waiters = persistenceWaiters
        persistenceWaiters.removeAll()
        waiters.forEach { $0.resume(returning: succeeded) }
        return succeeded
    }

    static func rateLabel(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(rate == rate.rounded() ? 1 : 2))) + " 倍"
    }

    private func receive(_ state: SpeechPlaybackState) {
        self.state = state
        if let locator = state.utterance?.locator {
            lastKnownLocator = locator
            pendingLocator = locator
            schedulePersistence()
        }
        if case let .failed(message) = state {
            errorMessage = message
        }
        if case .stopped = state {
            Task { await flushProgress() }
        }
        onNowPlayingChange?()
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, persistenceDelay] in
            do {
                let nanoseconds = UInt64(max(persistenceDelay, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flushScheduledProgress()
        }
    }

    private func flushScheduledProgress() async {
        persistenceTask = nil
        await flushProgress()
    }

    private func drainPendingProgress() async -> Bool {
        while let locator = pendingLocator {
            persistenceTask?.cancel()
            persistenceTask = nil
            pendingLocator = nil

            do {
                let position = try readingPosition(from: locator)
                try await repository.updatePosition(id: bookID, position: position)
            } catch {
                if pendingLocator == nil {
                    pendingLocator = locator
                }
                errorMessage = "无法保存听书进度。"
                return false
            }
        }
        return true
    }

    private func startPlayback(from locator: Locator?, announces: Bool) {
        guard !hasStarted else { return }
        invalidateInterruptionRecovery()
        hasStarted = true
        state = .loading
        service.start(from: locator)
        if announces { announce("开始播放") }
    }

    private func readingPosition(from locator: Locator) throws -> ReadingPosition {
        if let publication { return try publication.readingPosition(from: locator) }
        let data = try JSONSerialization.data(withJSONObject: locator.locations.json, options: [.sortedKeys])
        return ReadingPosition(
            href: locator.href.string,
            locationsJSON: String(data: data, encoding: .utf8),
            progression: locator.locations.totalProgression ?? locator.locations.progression ?? 0
        )
    }

    private static func clampedRate(_ rate: Double) -> Double {
        guard rate.isFinite else { return 1 }
        return min(max(rate, 0.5), 2)
    }

    private func canCompleteInterruptionRecovery(generation: Int) -> Bool {
        guard isInterruptionRecoveryCurrent(generation: generation) else { return false }
        if case .paused = state { return true }
        return false
    }

    private func isInterruptionRecoveryCurrent(generation: Int) -> Bool {
        generation == interruptionGeneration && wasPlayingBeforeInterruption
    }

    private func invalidateInterruptionRecovery() {
        interruptionGeneration &+= 1
        wasPlayingBeforeInterruption = false
    }

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            let generation = interruptionGeneration
            Task { [weak self] in
                await self?.completeInterruptionRecovery(shouldResume: shouldResume, generation: generation)
            }
        @unknown default:
            break
        }
    }

    @objc private func audioRouteChanged(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable,
              state.isPlaying
        else { return }
        pause(announces: false)
    }
}
