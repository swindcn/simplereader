import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    static let storageKey = "preferences.readerAndSpeech.v1"

    @Published private(set) var global: ReaderPreferences
    @Published private(set) var overrides: [UUID: ReaderPreferencesOverride]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let payload = try? JSONDecoder().decode(Payload.self, from: data),
           payload.version == Payload.currentVersion {
            global = payload.global.sanitized()
            overrides = payload.overrides.mapValues { $0.sanitized() }
        } else {
            var migrated = ReaderPreferences.defaults
            if let rate = defaults.object(forKey: "speech.rateMultiplier") as? Double {
                migrated.speechRate = rate
            }
            migrated.voiceIdentifier = defaults.string(forKey: "speech.voiceIdentifier")
            if let fontScale = defaults.object(forKey: "reader.epub.preferences.fontSize") as? Double {
                migrated.fontScale = fontScale
            }
            if let lineHeight = defaults.object(forKey: "reader.epub.preferences.lineHeight") as? Double {
                migrated.lineHeight = lineHeight
            }
            if let scroll = defaults.object(forKey: "reader.epub.preferences.scroll") as? Bool {
                migrated.layout = scroll ? .scroll : .paginated
            }
            if let rawTheme = defaults.string(forKey: "reader.epub.preferences.theme"),
               let theme = ReaderTheme(rawValue: rawTheme) {
                migrated.theme = theme
            }
            global = migrated.sanitized()
            overrides = [:]
            persist()
        }
        defaults.removeObject(forKey: "speech.rateMultiplier")
        defaults.removeObject(forKey: "speech.voiceIdentifier")
        for key in ["fontSize", "lineHeight", "scroll", "theme"] {
            defaults.removeObject(forKey: "reader.epub.preferences.\(key)")
        }
    }

    func setGlobal(_ preferences: ReaderPreferences) {
        global = preferences.sanitized()
        persist()
    }

    func resolved(for bookID: UUID?) -> ReaderPreferences {
        guard let bookID, let override = overrides[bookID] else { return global }
        return override.resolving(global)
    }

    func override(for bookID: UUID) -> ReaderPreferencesOverride? {
        overrides[bookID]
    }

    func hasOverride(for bookID: UUID) -> Bool {
        overrides[bookID] != nil
    }

    func setOverride(_ override: ReaderPreferencesOverride, for bookID: UUID) {
        var updated = overrides
        updated[bookID] = override.sanitized()
        overrides = updated
        persist()
    }

    func clearOverride(for bookID: UUID) {
        var updated = overrides
        updated.removeValue(forKey: bookID)
        overrides = updated
        persist()
    }

    func resetDefaults() {
        global = .defaults
        overrides = [:]
        persist()
    }

    private func persist() {
        let payload = Payload(
            version: Payload.currentVersion,
            global: global,
            overrides: overrides
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private struct Payload: Codable {
        static let currentVersion = 1
        let version: Int
        let global: ReaderPreferences
        let overrides: [UUID: ReaderPreferencesOverride]
    }
}
