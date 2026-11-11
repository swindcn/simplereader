import Foundation

enum AppLaunchRestorationPlan: Equatable, Sendable {
    case markImportFailed(bookID: UUID, originalFileURL: URL, error: UserFacingError)
    case reopenReader(bookID: UUID, position: ReadingPosition)
    case reopenListening(bookID: UUID, position: ReadingPosition, shouldAutoplay: Bool)
}

struct AppStateRestorer: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "PureVoice.AppStateRestorer.snapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordImport(bookID: UUID, originalFileURL: URL?, state: ImportState) {
        switch state {
        case .copying, .detecting, .converting, .openingPublication:
            guard let originalFileURL else { return }
            save(.importing(bookID: bookID, originalFileURL: originalFileURL))
        case .completed, .failed, .idle:
            clear()
        }
    }

    func recordReading(bookID: UUID, position: ReadingPosition) {
        clearIfReadingOrListeningSnapshot()
    }

    func recordListening(bookID: UUID, position: ReadingPosition, wasPlaying: Bool) {
        clearIfReadingOrListeningSnapshot()
    }

    func restoreLaunchState() -> AppLaunchRestorationPlan? {
        guard let snapshot = load() else { return nil }
        switch snapshot {
        case let .importing(bookID, originalFileURL):
            clear()
            return .markImportFailed(
                bookID: bookID,
                originalFileURL: originalFileURL,
                error: .importInterrupted
            )
        case .reading:
            clear()
            return nil
        case .listening:
            clear()
            return nil
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func clearIfReadingOrListeningSnapshot() {
        switch load() {
        case .reading, .listening:
            clear()
        case .importing, .none:
            break
        }
    }

    private enum Snapshot: Codable {
        case importing(bookID: UUID, originalFileURL: URL)
        case reading(bookID: UUID, position: ReadingPosition)
        case listening(bookID: UUID, position: ReadingPosition, wasPlaying: Bool)
    }
}
