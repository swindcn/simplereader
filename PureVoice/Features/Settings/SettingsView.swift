import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PreferencesStore
    let bookID: UUID?
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appStrings) private var strings
    @Environment(\.appLanguage) private var language
    @State private var confirmsReset = false

    init(store: PreferencesStore, bookID: UUID? = nil, showsCloseButton: Bool = false) {
        self.store = store
        self.bookID = bookID
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Form {
            if bookID == nil {
                Section(strings.displaySection) {
                    Picker(strings.appLanguage, selection: appLanguageBinding) {
                        ForEach(AppLanguage.allCases, id: \.self) { languagePreference in
                            Text(languagePreference.title(in: language)).tag(languagePreference)
                        }
                    }
                    .accessibilityLabel(strings.appLanguage)
                    .accessibilityValue(store.global.appLanguage.title(in: language))
                    .accessibilityIdentifier("settings.appLanguage")

                    Picker(strings.appFontSize, selection: appFontSizeBinding) {
                        ForEach(AppFontSize.allCases, id: \.self) { size in
                            Text(size.title(in: language)).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(strings.appFontSize)
                    .accessibilityValue(store.global.appFontSize.title(in: language))
                    .accessibilityIdentifier("settings.appFontSize")
                }
            }

            if let bookID {
                Section {
                    Toggle(strings.useGlobalSettings, isOn: usesGlobalForBookBinding(bookID: bookID))
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("settings.useGlobal")
                }
            }

            Section(strings.readingSection) {
                Picker(strings.fontFamily, selection: fontFamilyBinding) {
                    ForEach(ReaderFontFamily.allCases, id: \.self) { family in
                        Text(family.title(in: language)).tag(family)
                    }
                }
                .accessibilityLabel(strings.fontFamily)
                .accessibilityValue(resolved.fontFamily.title(in: language))
                .accessibilityIdentifier("settings.fontFamily")

                valueSlider(
                    title: strings.fontSize,
                    value: fontScaleBinding,
                    range: 0.8 ... 2,
                    step: 0.1,
                    identifier: "settings.fontScale"
                )
                valueSlider(
                    title: strings.lineHeight,
                    value: lineHeightBinding,
                    range: 1 ... 2.2,
                    step: 0.1,
                    identifier: "settings.lineHeight"
                )

                Picker(strings.theme, selection: themeBinding) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Text(theme.title(in: language)).tag(theme)
                    }
                }
                .accessibilityLabel(strings.theme)
                .accessibilityValue(resolved.theme.title(in: language))
                .accessibilityIdentifier("settings.theme")

                Picker(strings.readerMode, selection: layoutBinding) {
                    ForEach(ReaderLayout.allCases, id: \.self) { layout in
                        Text(layout.title(in: language)).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(strings.readerMode)
                .accessibilityValue(resolved.layout.title(in: language))
                .accessibilityIdentifier("settings.layout")
            }

            if bookID == nil {
                Section(strings.listeningSection) {
                    Picker(strings.defaultVoice, selection: voiceBinding) {
                        Text(strings.systemDefault).tag("")
                        ForEach(deviceVoices) { voice in
                            Text(voice.title).tag(voice.identifier)
                        }
                    }
                    .accessibilityLabel(strings.defaultVoice)
                    .accessibilityValue(selectedVoiceTitle)
                    .accessibilityIdentifier("settings.voice")

                    valueSlider(
                        title: strings.speechRate,
                        value: speechRateBinding,
                        range: 0.5 ... 2,
                        step: 0.25,
                        identifier: "settings.speechRate"
                    )
                }

                Section {
                    Button(strings.resetDefaults, role: .destructive) { confirmsReset = true }
                        .accessibilityIdentifier("settings.reset")
                }
            }
        }
        .navigationTitle(bookID == nil ? strings.settingsTab : strings.bookSettingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if showsCloseButton {
                    Button(strings.done) { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .confirmationDialog(strings.resetAllDefaultsTitle, isPresented: $confirmsReset) {
            Button(strings.resetDefaultConfirm, role: .destructive) { store.resetDefaults() }
                .accessibilityIdentifier("settings.reset.confirm")
            Button(strings.cancel, role: .cancel) {}
        }
    }

    private var resolved: ReaderPreferences { store.resolved(for: bookID) }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { store.global.appLanguage },
            set: { language in
                var global = store.global
                global.appLanguage = language
                store.setGlobal(global)
            }
        )
    }

    private var appFontSizeBinding: Binding<AppFontSize> {
        Binding(
            get: { store.global.appFontSize },
            set: { size in
                var global = store.global
                global.appFontSize = size
                store.setGlobal(global)
            }
        )
    }

    private var fontFamilyBinding: Binding<ReaderFontFamily> {
        readingBinding(\.fontFamily, override: \.fontFamily)
    }

    private var fontScaleBinding: Binding<Double> {
        readingBinding(\.fontScale, override: \.fontScale)
    }

    private var lineHeightBinding: Binding<Double> {
        readingBinding(\.lineHeight, override: \.lineHeight)
    }

    private var themeBinding: Binding<ReaderTheme> {
        readingBinding(\.theme, override: \.theme)
    }

    private var layoutBinding: Binding<ReaderLayout> {
        readingBinding(\.layout, override: \.layout)
    }

    private func readingBinding<Value>(
        _ globalKeyPath: WritableKeyPath<ReaderPreferences, Value>,
        override overrideKeyPath: WritableKeyPath<ReaderPreferencesOverride, Value?>
    ) -> Binding<Value> {
        Binding(
            get: { resolved[keyPath: globalKeyPath] },
            set: { value in
                if let bookID {
                    var override = store.override(for: bookID) ?? .init()
                    override[keyPath: overrideKeyPath] = value
                    store.setOverride(override, for: bookID)
                } else {
                    var global = store.global
                    global[keyPath: globalKeyPath] = value
                    store.setGlobal(global)
                }
            }
        )
    }

    private func usesGlobalForBookBinding(bookID: UUID) -> Binding<Bool> {
        Binding(
            get: { !store.hasOverride(for: bookID) },
            set: { usesGlobal in
                store.setUsesGlobal(usesGlobal, for: bookID)
            }
        )
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { store.global.voiceIdentifier ?? "" },
            set: { identifier in
                var global = store.global
                global.voiceIdentifier = identifier.isEmpty ? nil : identifier
                store.setGlobal(global)
            }
        )
    }

    private var speechRateBinding: Binding<Double> {
        Binding(
            get: { store.global.speechRate },
            set: { rate in
                var global = store.global
                global.speechRate = rate
                store.setGlobal(global)
            }
        )
    }

    private func valueSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(decimalLabel(value.wrappedValue)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(decimalLabel(value.wrappedValue))
                .accessibilityIdentifier(identifier)
        }
    }

    private func decimalLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value == value.rounded() ? 1 : 2)))
    }

    private var deviceVoices: [DeviceVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices().map {
            DeviceVoice(identifier: $0.identifier, title: "\($0.name)，\($0.language)")
        }
        if let saved = store.global.voiceIdentifier,
           !voices.contains(where: { $0.identifier == saved }) {
            return [DeviceVoice(identifier: saved, title: strings.savedVoice)] + voices
        }
        return voices.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var selectedVoiceTitle: String {
        guard let identifier = store.global.voiceIdentifier else { return strings.systemDefault }
        return deviceVoices.first { $0.identifier == identifier }?.title ?? strings.savedVoice
    }
}

private struct DeviceVoice: Identifiable {
    let identifier: String
    let title: String
    var id: String { identifier }
}
