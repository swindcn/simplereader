import ReadiumShared
import XCTest
@testable import PureVoice

@MainActor
final class RemoteCommandControllerTests: XCTestCase {
    func testMapsEveryRemoteCommandExactlyOnce() {
        let adapter = FakeRemoteCommandAdapter()
        var received: [RemoteCommand] = []
        let controller = RemoteCommandController(adapter: adapter) { received.append($0) }

        RemoteCommand.allCases.forEach { adapter.send($0) }

        XCTAssertEqual(received, RemoteCommand.allCases)
        withExtendedLifetime(controller) {}
    }

    func testStateEnablesOnlyValidCommandsAndUpdatesNowPlaying() {
        let adapter = FakeRemoteCommandAdapter()
        let controller = RemoteCommandController(adapter: adapter) { _ in }
        let metadata = NowPlayingMetadata(title: "测试书", author: "作者", rate: 1.25, isPlaying: true)

        controller.update(state: .playing(.placeholder), metadata: metadata)

        XCTAssertEqual(adapter.enabled[.play], false)
        XCTAssertEqual(adapter.enabled[.pause], true)
        XCTAssertEqual(adapter.enabled[.toggle], true)
        XCTAssertEqual(adapter.enabled[.next], true)
        XCTAssertEqual(adapter.enabled[.previous], true)
        XCTAssertEqual(adapter.metadata, metadata)

        controller.update(state: .paused(.placeholder), metadata: metadata)
        XCTAssertEqual(adapter.enabled[.play], true)
        XCTAssertEqual(adapter.enabled[.pause], false)
    }

    func testTeardownRemovesTargetsAndClearsNowPlaying() {
        let adapter = FakeRemoteCommandAdapter()
        var commandCount = 0
        let controller = RemoteCommandController(adapter: adapter) { _ in commandCount += 1 }
        controller.teardown()

        adapter.send(.play)

        XCTAssertEqual(commandCount, 0)
        XCTAssertEqual(adapter.teardownCount, 1)
        XCTAssertNil(adapter.metadata)
    }
}

@MainActor
private final class FakeRemoteCommandAdapter: RemoteCommandAdapting {
    var handler: ((RemoteCommand) -> Void)?
    var enabled: [RemoteCommand: Bool] = [:]
    var metadata: NowPlayingMetadata?
    private(set) var teardownCount = 0

    func setEnabled(_ enabled: Bool, for command: RemoteCommand) {
        self.enabled[command] = enabled
    }

    func updateNowPlaying(_ metadata: NowPlayingMetadata?) {
        self.metadata = metadata
    }

    func teardown() {
        teardownCount += 1
        handler = nil
    }

    func send(_ command: RemoteCommand) { handler?(command) }
}

private extension SpeechUtterance {
    static let placeholder = SpeechUtterance(
        text: "测试",
        locator: .init(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml
        )
    )
}
