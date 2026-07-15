import Foundation
@preconcurrency import MediaPlayer

enum RemoteCommand: CaseIterable, Equatable, Hashable {
    case play
    case pause
    case toggle
    case next
    case previous
}

struct NowPlayingMetadata: Equatable {
    let title: String
    let author: String
    let rate: Double
    let isPlaying: Bool
}

@MainActor
protocol RemoteCommandAdapting: AnyObject {
    var handler: ((RemoteCommand) -> Void)? { get set }
    func setEnabled(_ enabled: Bool, for command: RemoteCommand)
    func updateNowPlaying(_ metadata: NowPlayingMetadata?)
    func teardown()
}

@MainActor
final class RemoteCommandController {
    private let adapter: any RemoteCommandAdapting
    private let onCommand: (RemoteCommand) -> Void
    private var isTornDown = false

    init(
        adapter: any RemoteCommandAdapting = MPRemoteCommandAdapter(),
        onCommand: @escaping (RemoteCommand) -> Void
    ) {
        self.adapter = adapter
        self.onCommand = onCommand
        adapter.handler = { [weak self] command in
            guard let self, !isTornDown else { return }
            onCommand(command)
        }
    }

    func update(state: SpeechPlaybackState, metadata: NowPlayingMetadata) {
        let isActive: Bool
        switch state {
        case .playing, .paused: isActive = true
        case .loading, .stopped, .failed: isActive = false
        }
        adapter.setEnabled(isActive && !state.isPlaying, for: .play)
        adapter.setEnabled(isActive && state.isPlaying, for: .pause)
        adapter.setEnabled(isActive, for: .toggle)
        adapter.setEnabled(isActive, for: .next)
        adapter.setEnabled(isActive, for: .previous)
        adapter.updateNowPlaying(isActive ? metadata : nil)
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        adapter.handler = nil
        adapter.updateNowPlaying(nil)
        adapter.teardown()
    }
}

@MainActor
private final class MPRemoteCommandAdapter: RemoteCommandAdapting {
    var handler: ((RemoteCommand) -> Void)?

    private let center: MPRemoteCommandCenter
    private var targets: [(MPRemoteCommand, Any)] = []

    init(center: MPRemoteCommandCenter = .shared()) {
        self.center = center
        install(center.playCommand, command: .play)
        install(center.pauseCommand, command: .pause)
        install(center.togglePlayPauseCommand, command: .toggle)
        install(center.nextTrackCommand, command: .next)
        install(center.previousTrackCommand, command: .previous)
    }

    func setEnabled(_ enabled: Bool, for command: RemoteCommand) {
        mpCommand(for: command).isEnabled = enabled
    }

    func updateNowPlaying(_ metadata: NowPlayingMetadata?) {
        guard let metadata else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.author,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.isPlaying ? metadata.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: metadata.rate
        ]
    }

    func teardown() {
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        handler = nil
    }

    private func install(_ command: MPRemoteCommand, command mappedCommand: RemoteCommand) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.handler?(mappedCommand) }
            return .success
        }
        targets.append((command, target))
    }

    private func mpCommand(for command: RemoteCommand) -> MPRemoteCommand {
        switch command {
        case .play: center.playCommand
        case .pause: center.pauseCommand
        case .toggle: center.togglePlayPauseCommand
        case .next: center.nextTrackCommand
        case .previous: center.previousTrackCommand
        }
    }
}
