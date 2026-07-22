import SwiftUI
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

    func testAppFontSizesUseBoundedDynamicTypeValues() {
        XCTAssertEqual(AppFontSize.small.dynamicTypeSize, .medium)
        XCTAssertEqual(AppFontSize.medium.dynamicTypeSize, .large)
        XCTAssertEqual(AppFontSize.large.dynamicTypeSize, .xLarge)
        XCTAssertEqual(AppFontSize.extraLarge.dynamicTypeSize, .xxLarge)
    }

    func testDefaultsAreAccessibleReaderAndSpeechValues() {
        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.global, .defaults)
        XCTAssertEqual(store.global.fontFamily, .system)
        XCTAssertEqual(store.global.fontScale, 1)
        XCTAssertEqual(store.global.lineHeight, 1.5)
        XCTAssertEqual(store.global.theme, .sepia)
        XCTAssertEqual(store.global.layout, .paginated)
        XCTAssertEqual(store.global.appFontSize, .extraLarge)
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
        changed.appFontSize = .small
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

    func testBookLayoutOverridePreservesExistingThemeOverride() {
        let bookID = UUID()
        let store = PreferencesStore(defaults: defaults)
        store.setOverride(.init(theme: .dark), for: bookID)

        var override = store.override(for: bookID)!
        override.layout = .scroll
        store.setOverride(override, for: bookID)

        let resolved = store.resolved(for: bookID)
        XCTAssertEqual(resolved.theme, .dark)
        XCTAssertEqual(resolved.layout, .scroll)
    }

    func testDisablingGlobalPreferencesFreezesAllEffectiveBookPreferences() {
        let bookID = UUID()
        let store = PreferencesStore(defaults: defaults)
        let initial = ReaderPreferences(
            fontFamily: .serif,
            fontScale: 1.3,
            lineHeight: 1.8,
            theme: .sepia,
            layout: .scroll,
            voiceIdentifier: nil,
            speechRate: 1.5
        )
        store.setGlobal(initial)

        store.setUsesGlobal(false, for: bookID)
        store.setGlobal(
            ReaderPreferences(
                fontFamily: .sans,
                fontScale: 1.8,
                lineHeight: 2.1,
                theme: .dark,
                layout: .paginated,
                voiceIdentifier: "voice.changed",
                speechRate: 0.5
            )
        )

        XCTAssertTrue(store.hasOverride(for: bookID))
        XCTAssertEqual(store.resolved(for: bookID), initial)
        XCTAssertEqual(PreferencesStore(defaults: defaults).resolved(for: bookID), initial)

        store.setUsesGlobal(true, for: bookID)

        XCTAssertFalse(store.hasOverride(for: bookID))
        XCTAssertEqual(store.resolved(for: bookID).voiceIdentifier, "voice.changed")
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

    func testFuturePayloadFallsBackWithoutMutatingPayloadOrLegacyKeys() {
        let payload = try! JSONEncoder().encode(["version": 999, "futureField": 42])
        defaults.set(payload, forKey: PreferencesStore.storageKey)
        defaults.set(1.75, forKey: "speech.rateMultiplier")

        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.global, .defaults)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), payload)
        XCTAssertEqual(defaults.double(forKey: "speech.rateMultiplier"), 1.75)
    }

    func testCorruptCurrentPayloadFallsBackWithoutMutatingPayload() {
        let payload = Data(#"{"version":1,"global":{"fontFamily":"system"}}"#.utf8)
        defaults.set(payload, forKey: PreferencesStore.storageKey)

        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.global, .defaults)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), payload)
    }

    func testExplicitChangeReplacesUnsupportedPayloadWithCurrentPayload() {
        let futurePayload = try! JSONEncoder().encode(["version": 999])
        defaults.set(futurePayload, forKey: PreferencesStore.storageKey)
        let store = PreferencesStore(defaults: defaults)

        var changed = store.global
        changed.fontScale = 1.4
        store.setGlobal(changed)

        XCTAssertNotEqual(defaults.data(forKey: PreferencesStore.storageKey), futurePayload)
        XCTAssertEqual(PreferencesStore(defaults: defaults).global.fontScale, 1.4)
    }

    func testDynamicTypeMultipliesUserScaleWithUsableCap() {
        let preferences = ReaderPreferences(fontScale: 1.25)

        XCTAssertEqual(preferences.effectiveFontScale(for: .large), 1.25)
        XCTAssertEqual(preferences.effectiveFontScale(for: .accessibilityExtraExtraExtraLarge), 2.5)
        XCTAssertEqual(ReaderPreferences(fontScale: 2).effectiveFontScale(for: .accessibilityExtraExtraExtraLarge), 3)
    }

    func testReaderThemeProvidesMatchingReaderChromeColors() {
        XCTAssertEqual(ReaderTheme.sepia.readerAppearance(usesDarkSystemTheme: false).backgroundColor, .pureVoiceSepiaBackground)
        XCTAssertEqual(ReaderTheme.sepia.readerAppearance(usesDarkSystemTheme: false).chromeBackgroundColor, .pureVoiceSepiaChrome)
        XCTAssertEqual(ReaderTheme.dark.readerAppearance(usesDarkSystemTheme: false).backgroundColor, .black)
        XCTAssertEqual(ReaderTheme.system.readerAppearance(usesDarkSystemTheme: true).backgroundColor, .black)
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
        XCTAssertNotNil(defaults.data(forKey: PreferencesStore.storageKey))
    }


    func testPreferenceSubmissionDecisionSkipsLocationAndOrdinaryUpdatesAndSubmitsOneRealChange() {
        var decision = PreferenceSubmissionDecision(initialValue: "initial")
        var submissions: [String] = []

        func update(preferences: String, location: Int) {
            _ = location
            if decision.shouldSubmit(preferences) {
                submissions.append(preferences)
            }
        }

        update(preferences: "initial", location: 1)
        update(preferences: "initial", location: 2)
        update(preferences: "changed", location: 2)
        update(preferences: "changed", location: 2)

        XCTAssertEqual(submissions, ["changed"])
    }

    func testScrollAutoAdvanceRequiresUserGestureAtBottomInScrollLayout() {
        var policy = EPUBScrollAutoAdvancePolicy(bottomThreshold: 80, cooldown: 1)

        XCTAssertFalse(policy.shouldAdvance(
            isScrollLayout: false,
            isVoiceOverRunning: false,
            isUserScrolling: true,
            contentOffsetY: 920,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 10
        ))
        XCTAssertFalse(policy.shouldAdvance(
            isScrollLayout: true,
            isVoiceOverRunning: true,
            isUserScrolling: true,
            contentOffsetY: 920,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 10
        ))
        XCTAssertFalse(policy.shouldAdvance(
            isScrollLayout: true,
            isVoiceOverRunning: false,
            isUserScrolling: false,
            contentOffsetY: 920,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 10
        ))
        XCTAssertTrue(policy.shouldAdvance(
            isScrollLayout: true,
            isVoiceOverRunning: false,
            isUserScrolling: true,
            contentOffsetY: 830,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 10
        ))
    }

    func testScrollAutoAdvanceDebouncesRepeatedBottomEvents() {
        var policy = EPUBScrollAutoAdvancePolicy(bottomThreshold: 80, cooldown: 1)

        XCTAssertTrue(policy.shouldAdvance(
            isScrollLayout: true,
            isVoiceOverRunning: false,
            isUserScrolling: true,
            contentOffsetY: 830,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 10
        ))
        XCTAssertFalse(policy.shouldAdvance(
            isScrollLayout: true,
            isVoiceOverRunning: false,
            isUserScrolling: true,
            contentOffsetY: 870,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 10.5
        ))
        XCTAssertTrue(policy.shouldAdvance(
            isScrollLayout: true,
            isVoiceOverRunning: false,
            isUserScrolling: true,
            contentOffsetY: 870,
            viewportHeight: 600,
            contentHeight: 1_500,
            now: 11.1
        ))
    }
}
