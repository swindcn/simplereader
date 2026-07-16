import XCTest
@testable import PureVoice

@MainActor
final class PreferencesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PreferencesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsAreAccessibleReaderAndSpeechValues() {
        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.global, .defaults)
        XCTAssertEqual(store.global.fontFamily, .system)
        XCTAssertEqual(store.global.fontScale, 1)
        XCTAssertEqual(store.global.lineHeight, 1.5)
        XCTAssertEqual(store.global.theme, .system)
        XCTAssertEqual(store.global.layout, .paginated)
        XCTAssertEqual(store.global.speechRate, 1)
        XCTAssertNil(store.global.voiceIdentifier)
    }

    func testGlobalPreferencesPersistAcrossStoreInstances() {
        let store = PreferencesStore(defaults: defaults)
        var changed = store.global
        changed.fontFamily = .serif
        changed.fontScale = 1.4
        changed.lineHeight = 1.8
        changed.theme = .sepia
        changed.layout = .scroll
        changed.voiceIdentifier = "voice.test"
        changed.speechRate = 1.5
        store.setGlobal(changed)

        XCTAssertEqual(PreferencesStore(defaults: defaults).global, changed)
    }

    func testInvalidNumericValuesAreClampedAndNonfiniteValuesFallBack() {
        let store = PreferencesStore(defaults: defaults)
        var changed = store.global
        changed.fontScale = 8
        changed.lineHeight = -2
        changed.speechRate = .infinity
        store.setGlobal(changed)

        XCTAssertEqual(store.global.fontScale, 2)
        XCTAssertEqual(store.global.lineHeight, 1)
        XCTAssertEqual(store.global.speechRate, 1)

        changed.fontScale = .nan
        changed.lineHeight = .infinity
        changed.speechRate = 0.1
        store.setGlobal(changed)
        XCTAssertEqual(store.global.fontScale, 1)
        XCTAssertEqual(store.global.lineHeight, 1.5)
        XCTAssertEqual(store.global.speechRate, 0.5)
    }

    func testSparseBookOverrideInheritsSubsequentGlobalChanges() {
        let bookID = UUID()
        let store = PreferencesStore(defaults: defaults)
        store.setOverride(.init(theme: .dark), for: bookID)

        var global = store.global
        global.fontScale = 1.6
        global.lineHeight = 2
        store.setGlobal(global)

        let resolved = store.resolved(for: bookID)
        XCTAssertEqual(resolved.theme, .dark)
        XCTAssertEqual(resolved.fontScale, 1.6)
        XCTAssertEqual(resolved.lineHeight, 2)
        XCTAssertEqual(PreferencesStore(defaults: defaults).resolved(for: bookID), resolved)
    }

    func testClearOverrideAndResetDefaults() {
        let bookID = UUID()
        let store = PreferencesStore(defaults: defaults)
        store.setOverride(.init(layout: .scroll), for: bookID)
        store.clearOverride(for: bookID)
        XCTAssertFalse(store.hasOverride(for: bookID))

        var changed = store.global
        changed.fontScale = 1.8
        store.setGlobal(changed)
        store.setOverride(.init(theme: .dark), for: bookID)
        store.resetDefaults()

        XCTAssertEqual(store.global, .defaults)
        XCTAssertFalse(store.hasOverride(for: bookID))
        XCTAssertEqual(PreferencesStore(defaults: defaults).global, .defaults)
    }

    func testCorruptOrUnsupportedPayloadFallsBackWithoutCrashing() {
        defaults.set(Data("not-json".utf8), forKey: PreferencesStore.storageKey)
        XCTAssertEqual(PreferencesStore(defaults: defaults).global, .defaults)

        defaults.set(try! JSONEncoder().encode(["version": 999]), forKey: PreferencesStore.storageKey)
        XCTAssertEqual(PreferencesStore(defaults: defaults).global, .defaults)
    }

    func testDynamicTypeMultipliesUserScaleWithUsableCap() {
        let preferences = ReaderPreferences(fontScale: 1.25)

        XCTAssertEqual(preferences.effectiveFontScale(for: .large), 1.25)
        XCTAssertEqual(preferences.effectiveFontScale(for: .accessibilityExtraExtraExtraLarge), 2.5)
        XCTAssertEqual(ReaderPreferences(fontScale: 2).effectiveFontScale(for: .accessibilityExtraExtraExtraLarge), 3)
    }

    func testLegacySpeechKeysMigrateOnceIntoUnifiedPayload() {
        defaults.set(1.75, forKey: "speech.rateMultiplier")
        defaults.set("legacy.voice", forKey: "speech.voiceIdentifier")

        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.global.speechRate, 1.75)
        XCTAssertEqual(store.global.voiceIdentifier, "legacy.voice")
        XCTAssertNil(defaults.object(forKey: "speech.rateMultiplier"))
        XCTAssertNil(defaults.object(forKey: "speech.voiceIdentifier"))
    }

    func testLegacyReaderKeysMigrateIntoUnifiedPayload() {
        defaults.set(1.4, forKey: "reader.epub.preferences.fontSize")
        defaults.set(1.9, forKey: "reader.epub.preferences.lineHeight")
        defaults.set(true, forKey: "reader.epub.preferences.scroll")
        defaults.set("sepia", forKey: "reader.epub.preferences.theme")

        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.global.fontScale, 1.4)
        XCTAssertEqual(store.global.lineHeight, 1.9)
        XCTAssertEqual(store.global.layout, .scroll)
        XCTAssertEqual(store.global.theme, .sepia)
        XCTAssertNil(defaults.object(forKey: "reader.epub.preferences.fontSize"))
    }
}
