import AVFoundation
import Foundation
@preconcurrency import ReadiumShared

struct SpeechUtterance: Equatable {
    let text: String
    let locator: Locator
}

enum SpeechPlaybackState: Equatable {
    case loading
    case playing(SpeechUtterance)
    case paused(SpeechUtterance)
    case stopped
    case failed(String)

    var utterance: SpeechUtterance? {
        switch self {
        case let .playing(utterance), let .paused(utterance): utterance
        case .loading, .stopped, .failed: nil
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

struct SpeechVoice: Equatable, Identifiable {
    enum Gender: Equatable {
        case female
        case male
        case unspecified
    }

    enum Quality: Int, Equatable {
        case lower
        case low
        case medium
        case high
        case higher
    }

    let identifier: String
    let name: String
    let language: String
    let gender: Gender
    let quality: Quality?

    var id: String { identifier }

    var genderLabel: String {
        switch gender {
        case .female: "女声"
        case .male: "男声"
        case .unspecified: "未指定"
        }
    }

    var displayName: String { "\(name)，\(genderLabel)" }
}

@MainActor
protocol SpeechService: AnyObject {
    var state: SpeechPlaybackState { get }
    var onStateChange: ((SpeechPlaybackState) -> Void)? { get set }
    var voices: [SpeechVoice] { get }
    var rate: Double { get set }
    var selectedVoiceIdentifier: String? { get set }

    func start(from locator: Locator?)
    func pause()
    func resume()
    func stop()
    func previous()
    func next()
}

@MainActor
protocol AudioSessionActivating: AnyObject {
    func activate() async throws
}

@MainActor
final class SystemAudioSessionActivator: AudioSessionActivating {
    func activate() async throws {
        try AVAudioSession.sharedInstance().setActive(true)
    }
}
