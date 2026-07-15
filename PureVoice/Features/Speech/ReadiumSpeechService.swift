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
            let selected = newValue.flatMap { identifier in
                voices.first { $0.identifier == identifier }?.identifier
            } ?? voices.first?.identifier
            synthesizer.config.voiceIdentifier = selected
        }
    }

    private let synthesizer: PublicationSpeechSynthesizer
    private let rateDelegate: RateApplyingAVDelegate

    init?(publication openedPublication: OpenedPublication) {
        let publication = openedPublication.readiumPublication
        guard PublicationSpeechSynthesizer.canSpeak(publication: publication) else { return nil }

        let languageCode = publication.metadata.languages.first
            ?? Locale.preferredLanguages.first
            ?? "zh-CN"
        let defaultLanguage = Language(code: .bcp47(languageCode))
        let rateDelegate = RateApplyingAVDelegate()
        guard let synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            config: .init(defaultLanguage: defaultLanguage),
            audioSessionConfig: .init(
                category: .playback,
                mode: .spokenAudio,
                routeSharingPolicy: .longFormAudio,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            ),
            engineFactory: { AVTTSEngine(delegate: rateDelegate) }
        ) else { return nil }

        self.synthesizer = synthesizer
        self.rateDelegate = rateDelegate
        voices = Self.orderedVoices(
            synthesizer.availableVoices.map(SpeechVoice.init(ttsVoice:)),
            preferredLanguage: languageCode
        )
        synthesizer.delegate = self
    }

    func start(from locator: Locator?) { synthesizer.start(from: locator) }
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
        case let .playing(utterance, range: _):
            publish(.playing(.init(text: utterance.text, locator: utterance.locator)))
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

@MainActor
private final class RateApplyingAVDelegate: NSObject {
    var rateMultiplier: Double = 1
}

extension RateApplyingAVDelegate: @MainActor AVTTSEngineDelegate {
    func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
        utterance.rate = Float(ReadiumSpeechService.avSpeechRate(for: rateMultiplier))
    }
}

private extension SpeechVoice {
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
    init(ttsGender: TTSVoice.Gender) {
        switch ttsGender {
        case .female: self = .female
        case .male: self = .male
        case .unspecified: self = .unspecified
        }
    }
}

private extension SpeechVoice.Quality {
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
