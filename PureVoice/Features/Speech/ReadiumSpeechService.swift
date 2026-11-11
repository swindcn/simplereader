import AVFoundation
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

@MainActor
final class ReadiumSpeechService: SpeechService {
    private(set) var state: SpeechPlaybackState = .stopped
    var onStateChange: ((SpeechPlaybackState) -> Void)?
    let voices: [SpeechVoice]

    var rate: Double = 1 {
        didSet {
            rate = min(max(rate.isFinite ? rate : 1, 0.5), 2)
            rateDelegate.rateMultiplier = rate
        }
    }

    var selectedVoiceIdentifier: String? {
        get { synthesizer.config.voiceIdentifier }
        set {
            synthesizer.config.voiceIdentifier = Self.resolvedVoiceIdentifier(
                requested: newValue,
                availableVoices: voices
            )
        }
    }

    private let synthesizer: PublicationSpeechSynthesizer
    private let rateDelegate: RateApplyingAVDelegate
    private let firstReadableLocator: Locator?
    private let navigationResourceHREFs: Set<String>

    init?(publication openedPublication: OpenedPublication) {
        let publication = openedPublication.readiumPublication
        guard PublicationSpeechSynthesizer.canSpeak(publication: publication) else { return nil }

        let languageCode = publication.metadata.languages.first
            ?? Locale.preferredLanguages.first
            ?? "zh-CN"
        let defaultLanguage = Language(code: .bcp47(languageCode))
        let rateDelegate = RateApplyingAVDelegate()
        let engineFactory = Self.makeSpeechEngineFactory(delegate: rateDelegate)
        guard let synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            config: .init(defaultLanguage: defaultLanguage),
            audioSessionConfig: .init(
                category: .playback,
                mode: .spokenAudio,
                routeSharingPolicy: .longFormAudio,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            ),
            engineFactory: engineFactory
        ) else { return nil }

        self.synthesizer = synthesizer
        self.rateDelegate = rateDelegate
        let navigationResources = PublicationReadingFilter.navigationResourceHREFs(
            in: ReaderViewModel.flatten(openedPublication.tableOfContents)
        )
        navigationResourceHREFs = navigationResources
        firstReadableLocator = publication.readingOrder.first { link in
            !PublicationReadingFilter.isLikelyNavigationEntry(title: link.title, href: link.href)
                && !navigationResources.containsResource(matching: link.href)
        }.flatMap { link in
            AnyURL(string: link.href).map { href in
                Locator(
                    href: href,
                    mediaType: .xhtml,
                    title: link.title,
                    locations: .init(progression: 0)
                )
            }
        }
        voices = Self.deviceVoices(preferredLanguage: languageCode)
        synthesizer.delegate = self
    }

    func start(from locator: Locator?) {
        let startLocator = locator.flatMap { locator in
            let resource = locator.href.string.resourceHREF
            return PublicationReadingFilter.isLikelyNavigationResource(resource)
                || navigationResourceHREFs.containsResource(matching: resource)
                ? firstReadableLocator
                : locator
        } ?? firstReadableLocator
        synthesizer.start(from: startLocator)
    }
    func pause() { synthesizer.pause() }
    func resume() { synthesizer.resume() }
    func stop() { synthesizer.stop() }
    func previous() { synthesizer.previous() }
    func next() { synthesizer.next() }

    nonisolated static func avSpeechRate(for multiplier: Double) -> Double {
        let multiplier = min(max(multiplier.isFinite ? multiplier : 1, 0.5), 2)
        let minimum = Double(AVSpeechUtteranceMinimumSpeechRate)
        let normal = Double(AVSpeechUtteranceDefaultSpeechRate)
        let maximum = Double(AVSpeechUtteranceMaximumSpeechRate)
        return min(max(normal * multiplier, minimum), maximum)
    }

    nonisolated static func makeSpeechEngineFactory(
        delegate: RateApplyingAVDelegate
    ) -> @Sendable () -> AVTTSEngine {
        { AVTTSEngine(delegate: delegate) }
    }

    static func orderedVoices(
        _ voices: [SpeechVoice],
        preferredLanguage: String?
    ) -> [SpeechVoice] {
        let preferredBase = preferredLanguage.map(Self.baseLanguage)
        let compatible = preferredBase.map { base in
            voices.filter { Self.baseLanguage($0.language) == base }
        } ?? voices

        let candidates = compatible.isEmpty ? voices : compatible
        return candidates.sorted { lhs, rhs in
            let lhsQuality = lhs.quality?.rawValue ?? -1
            let rhsQuality = rhs.quality?.rawValue ?? -1
            if lhsQuality != rhsQuality { return lhsQuality > rhsQuality }
            let lhsGender = genderRank(lhs.gender)
            let rhsGender = genderRank(rhs.gender)
            if lhsGender != rhsGender { return lhsGender < rhsGender }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.identifier < rhs.identifier
        }
    }

    static func deviceVoices(preferredLanguage: String?) -> [SpeechVoice] {
        orderedVoices(
            AVSpeechSynthesisVoice.speechVoices().map(SpeechVoice.init(systemVoice:)),
            preferredLanguage: preferredLanguage
        )
    }

    static func resolvedVoiceIdentifier(
        requested: String?,
        availableVoices: [SpeechVoice]
    ) -> String? {
        guard let requested else { return nil }
        return availableVoices.first { $0.identifier == requested }?.identifier
            ?? availableVoices.first?.identifier
    }

    static func playbackLocator(
        utteranceLocator: Locator,
        rangeLocator: Locator?
    ) -> Locator {
        rangeLocator ?? utteranceLocator
    }

    private static func baseLanguage(_ language: String) -> String {
        language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased()
            ?? language.lowercased()
    }

    private static func genderRank(_ gender: SpeechVoice.Gender) -> Int {
        switch gender {
        case .female: 0
        case .male: 1
        case .unspecified: 2
        }
    }

    private func publish(_ newState: SpeechPlaybackState) {
        state = newState
        onStateChange?(newState)
    }
}

private extension Set where Element == String {
    func containsResource(matching href: String) -> Bool {
        contains { PublicationReadingFilter.resourceHREFsMatch($0, href) }
    }
}

extension ReadiumSpeechService: PublicationSpeechSynthesizerDelegate {
    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        switch state {
        case .stopped:
            publish(.stopped)
        case let .paused(utterance):
            publish(.paused(.init(text: utterance.text, locator: utterance.locator)))
        case let .playing(utterance, range: range):
            publish(.playing(.init(
                text: utterance.text,
                locator: Self.playbackLocator(
                    utteranceLocator: utterance.locator,
                    rangeLocator: range
                )
            )))
        }
    }

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        publish(.failed("无法播放当前句，请更换声音后重试。"))
    }
}

final class RateApplyingAVDelegate: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var protectedRateMultiplier: Double = 1

    var rateMultiplier: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return protectedRateMultiplier
        }
        set {
            lock.lock()
            protectedRateMultiplier = newValue
            lock.unlock()
        }
    }
}

extension RateApplyingAVDelegate: AVTTSEngineDelegate {
    func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
        utterance.rate = Float(ReadiumSpeechService.avSpeechRate(for: rateMultiplier))
    }
}

private extension SpeechVoice {
    init(systemVoice voice: AVSpeechSynthesisVoice) {
        self.init(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            gender: .init(systemGender: voice.gender),
            quality: .init(systemQuality: voice.quality)
        )
    }

    init(ttsVoice voice: TTSVoice) {
        self.init(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language.code.bcp47,
            gender: .init(ttsGender: voice.gender),
            quality: voice.quality.flatMap(Quality.init(ttsQuality:))
        )
    }
}

private extension SpeechVoice.Gender {
    init(systemGender: AVSpeechSynthesisVoiceGender) {
        switch systemGender {
        case .female:
            self = .female
        case .male:
            self = .male
        case .unspecified:
            self = .unspecified
        @unknown default:
            self = .unspecified
        }
    }

    init(ttsGender: TTSVoice.Gender) {
        switch ttsGender {
        case .female: self = .female
        case .male: self = .male
        case .unspecified: self = .unspecified
        }
    }
}

private extension SpeechVoice.Quality {
    init(systemQuality: AVSpeechSynthesisVoiceQuality) {
        switch systemQuality.rawValue {
        case 0:
            self = .medium
        case 1:
            self = .high
        default:
            self = .higher
        }
    }

    init(ttsQuality: TTSVoice.Quality) {
        switch ttsQuality {
        case .lower: self = .lower
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .higher: self = .higher
        }
    }
}
