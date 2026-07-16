import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PreferencesStore
    let bookID: UUID?
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsReset = false
    @State private var usesGlobalForBook: Bool

    init(store: PreferencesStore, bookID: UUID? = nil, showsCloseButton: Bool = false) {
        self.store = store
        self.bookID = bookID
        self.showsCloseButton = showsCloseButton
        _usesGlobalForBook = State(initialValue: bookID.map { !store.hasOverride(for: $0) } ?? false)
    }

    var body: some View {
        Form {
            if let bookID {
                Section {
                    Toggle("使用全局设置", isOn: $usesGlobalForBook)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("settings.useGlobal")
                        .onChange(of: usesGlobalForBook) { usesGlobal in
                            if usesGlobal {
                                store.clearOverride(for: bookID)
                            } else {
                                store.setOverride(.init(), for: bookID)
                            }
                        }
                }
            }

            Section("阅读") {
                Picker("字体", selection: fontFamilyBinding) {
                    ForEach(ReaderFontFamily.allCases, id: \.self) { family in
                        Text(family.title).tag(family)
                    }
                }
                .accessibilityLabel("字体")
                .accessibilityValue(resolved.fontFamily.title)
                .accessibilityIdentifier("settings.fontFamily")

                valueSlider(
                    title: "字号",
                    value: fontScaleBinding,
                    range: 0.8 ... 2,
                    step: 0.1,
                    identifier: "settings.fontScale"
                )
                valueSlider(
                    title: "行距",
                    value: lineHeightBinding,
                    range: 1 ... 2.2,
                    step: 0.1,
                    identifier: "settings.lineHeight"
                )

                Picker("主题", selection: themeBinding) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .accessibilityLabel("主题")
                .accessibilityValue(resolved.theme.title)
                .accessibilityIdentifier("settings.theme")

                Picker("阅读模式", selection: layoutBinding) {
                    ForEach(ReaderLayout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("阅读模式")
                .accessibilityValue(resolved.layout.title)
                .accessibilityIdentifier("settings.layout")
            }

            if bookID == nil {
                Section("听书") {
                    Picker("默认声音", selection: voiceBinding) {
                        Text("系统默认").tag("")
                        ForEach(deviceVoices) { voice in
                            Text(voice.title).tag(voice.identifier)
                        }
                    }
                    .accessibilityLabel("默认声音")
                    .accessibilityValue(selectedVoiceTitle)
                    .accessibilityIdentifier("settings.voice")

                    valueSlider(
                        title: "语速",
                        value: speechRateBinding,
                        range: 0.5 ... 2,
                        step: 0.25,
                        identifier: "settings.speechRate"
                    )
                }

                Section {
                    Button("恢复默认设置", role: .destructive) { confirmsReset = true }
                        .accessibilityIdentifier("settings.reset")
                }
            }
        }
        .navigationTitle(bookID == nil ? "设置" : "本书设置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if showsCloseButton {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .confirmationDialog("恢复所有默认设置？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) { store.resetDefaults() }
                .accessibilityIdentifier("settings.reset.confirm")
            Button("取消", role: .cancel) {}
        }
    }

    private var resolved: ReaderPreferences { store.resolved(for: bookID) }

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
                    usesGlobalForBook = false
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
            return [DeviceVoice(identifier: saved, title: "已保存的声音")] + voices
        }
        return voices.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var selectedVoiceTitle: String {
        guard let identifier = store.global.voiceIdentifier else { return "系统默认" }
        return deviceVoices.first { $0.identifier == identifier }?.title ?? "已保存的声音"
    }
}

private struct DeviceVoice: Identifiable {
    let identifier: String
    let title: String
    var id: String { identifier }
}
