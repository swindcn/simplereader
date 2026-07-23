import SwiftUI
import UIKit
@preconcurrency import ReadiumShared

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appStrings) private var strings
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var commands = EPUBNavigatorCommands()
    @ObservedObject private var preferencesStore: PreferencesStore
    @State private var isSettingsPresented = false
    @State private var isChromeVisible = true
    @State private var chromeHideTask: Task<Void, Never>?
    @AccessibilityFocusState private var isChromeFocused: Bool

    private let onListen: (OpenedPublication, Locator?) -> Void
    private let onSettings: () -> Void
    private let listeningReturnLocator: Locator?
    private let activeListeningLocator: Locator?

    init(
        book: Book,
        repository: any BookRepository,
        preferencesStore: PreferencesStore? = nil,
        appStateRestorer: AppStateRestorer? = nil,
        onListen: @escaping (OpenedPublication, Locator?) -> Void = { _, _ in },
        onSettings: @escaping () -> Void = {},
        listeningReturnLocator: Locator? = nil,
        activeListeningLocator: Locator? = nil
    ) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            book: book,
            repository: repository,
            appStateRestorer: appStateRestorer
        ))
        self.preferencesStore = preferencesStore ?? PreferencesStore()
        self.onListen = onListen
        self.onSettings = onSettings
        self.listeningReturnLocator = listeningReturnLocator
        self.activeListeningLocator = activeListeningLocator
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(strings.openingBook)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.openedPublication == nil {
                failureView(message)
            } else if let publication = viewModel.openedPublication {
                reader(publication)
            } else {
                ProgressView()
            }
        }
        .background(Color(uiColor: readerAppearance.backgroundColor).ignoresSafeArea())
        .preferredColorScheme(preferredColorScheme)
        .task { await viewModel.open() }
        .onDisappear { Task { await viewModel.flushProgress() } }
        .onDisappear { cancelChromeAutoHide() }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                Task { await viewModel.flushProgress() }
            }
        }
        .onChange(of: listeningReturnLocator) { locator in
            if let locator { viewModel.returnFromListening(at: locator) }
        }
        .onChange(of: activeListeningLocator) { locator in
            if let locator {
                viewModel.followListening(at: locator)
            } else {
                viewModel.clearSpeechHighlight()
            }
        }
        .onChange(of: isChromeFocused) { focused in
            if focused {
                cancelChromeAutoHide()
            } else {
                scheduleChromeAutoHide()
            }
        }
        .sheet(isPresented: $viewModel.isTableOfContentsPresented) {
            tableOfContents
                .appFontSize(preferencesStore.global.appFontSize)
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationView {
                SettingsView(store: preferencesStore, bookID: viewModel.bookID, showsCloseButton: true)
            }
            .navigationViewStyle(.stack)
            .appFontSize(preferencesStore.global.appFontSize)
        }
        .alert(strings.readerNotice, isPresented: nonfatalErrorPresented) {
            Button(strings.ok, role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? strings.unknownError)
        }
    }

    private func reader(_ publication: OpenedPublication) -> some View {
        ZStack(alignment: .topLeading) {
            if currentPreferences.layout == .scroll {
                ContinuousReaderContentView(
                    publication: publication,
                    initialLocator: viewModel.currentLocator ?? viewModel.initialLocator,
                    navigationRequest: viewModel.navigationRequest,
                    speechHighlightLocator: viewModel.speechHighlightLocator,
                    preferences: currentPreferences,
                    dynamicTypeCategory: readerFontCategory,
                    appearance: readerAppearance,
                    onLocationChange: viewModel.receive(locator:),
                    onError: viewModel.reportNavigatorError
                )
                .accessibilityLabel(strings.readingContent)
            } else {
                EPUBNavigatorController(
                    publication: publication,
                    initialLocation: viewModel.currentLocator ?? viewModel.initialLocator,
                    preferences: currentPreferences.epubPreferences(
                        dynamicTypeCategory: readerFontCategory,
                        usesDarkSystemTheme: colorScheme == .dark
                    ),
                    navigationRequest: viewModel.navigationRequest,
                    speechHighlightLocator: viewModel.speechHighlightLocator,
                    commands: commands,
                    onLocationChange: viewModel.receive(locator:),
                    onNavigationFailure: viewModel.reportNavigationFailure,
                    onError: viewModel.reportNavigatorError
                )
                .id(currentPreferences.layout)
                .accessibilityLabel(strings.readingContent)
            }

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black.opacity(0.001))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleReaderChrome)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(proxy.size.height / 3, 120))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(isChromeVisible ? strings.hideReaderControls : strings.showReaderControls)
                        .accessibilityIdentifier(isChromeVisible ? "reader.chromeDismissArea" : "reader.contentTapArea")
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)

            if isChromeVisible {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        AccessibilityChapterHeading(
                            title: displayedHeading(for: publication),
                            focusGeneration: viewModel.chapterFocusGeneration
                        )
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 64)

                ReaderHeaderToolbar(
                    onBack: closeReader,
                    onTableOfContents: { viewModel.isTableOfContentsPresented = true },
                    backgroundColor: Color(uiColor: readerAppearance.chromeBackgroundColor)
                )
                    }
                    .background(Color(uiColor: readerAppearance.chromeBackgroundColor))
                    .accessibilityElement(children: .contain)
                    .accessibilityFocused($isChromeFocused)
                    .accessibilityIdentifier("reader.chrome")
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer(minLength: 0)

                ReaderToolbar(
                    onListen: { onListen(publication, viewModel.currentLocator) },
                    onSettings: {
                        isSettingsPresented = true
                        onSettings()
                    },
                    backgroundColor: Color(uiColor: readerAppearance.chromeBackgroundColor)
                )
                    .background(Color(uiColor: readerAppearance.chromeBackgroundColor))
                    .accessibilityElement(children: .contain)
                    .accessibilityFocused($isChromeFocused)
                    .accessibilityIdentifier("reader.bottomToolbar")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(2)
            }
#if DEBUG
            if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_READER_EPUB"] != nil {
                Text(debugLocatorLabel)
                    .font(.system(size: 1))
                    .frame(width: 2, height: 2)
                    .foregroundStyle(.clear)
                    .accessibilityLabel(debugLocatorLabel)
                    .accessibilityIdentifier("reader.debug.locator")
            }
#endif
        }
        .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        .onAppear { scheduleChromeAutoHide() }
    }

    private var tableOfContents: some View {
        NavigationView {
            List(viewModel.tableOfContents) { entry in
                Button {
                    viewModel.selectChapter(entry)
                } label: {
                    Text(entry.title)
                        .padding(.leading, CGFloat(entry.level) * 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("reader.toc.\(entry.id)")
            }
            .navigationTitle(strings.tableOfContents)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.close) { viewModel.isTableOfContentsPresented = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(strings.cannotOpenBook)
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(strings.backToLibrary, action: closeReader)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reader.failure.back")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nonfatalErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && viewModel.openedPublication != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private var currentPreferences: ReaderPreferences {
        preferencesStore.resolved(for: viewModel.bookID)
    }

    private var readerFontCategory: ReaderDynamicTypeCategory {
        .large
    }

    private var readerAppearance: ReaderThemeAppearance {
        currentPreferences.theme.readerAppearance(usesDarkSystemTheme: colorScheme == .dark)
    }

    private var preferredColorScheme: ColorScheme? {
        switch currentPreferences.theme {
        case .system:
            nil
        case .light, .sepia:
            .light
        case .dark:
            .dark
        }
    }

    private func closeReader() {
        Task {
            if await viewModel.flushProgress() {
                dismiss()
            }
        }
    }

    private func showReaderChrome() {
        isChromeVisible = true
        scheduleChromeAutoHide()
    }

    private func hideReaderChrome() {
        isChromeVisible = false
        cancelChromeAutoHide()
    }

    private func toggleReaderChrome() {
        if isChromeVisible {
            hideReaderChrome()
        } else {
            showReaderChrome()
        }
    }

    private func scheduleChromeAutoHide() {
        cancelChromeAutoHide()
        guard isChromeVisible else { return }
        guard !isChromeFocused else { return }
        chromeHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, !isChromeFocused else { return }
            isChromeVisible = false
        }
    }

    private func cancelChromeAutoHide() {
        chromeHideTask?.cancel()
        chromeHideTask = nil
    }

    private func displayedHeading(for publication: OpenedPublication) -> String {
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_READER_HEADING"] {
            return override
        }
#endif
        return viewModel.chapterTitle.isEmpty ? publication.title : viewModel.chapterTitle
    }

#if DEBUG
    private var debugLocatorLabel: String {
        guard let locator = viewModel.currentLocator else { return "等待定位" }
        let progression = locator.locations.totalProgression ?? locator.locations.progression ?? 0
        return "\(locator.href.string)|\(progression)"
    }
#endif
}

private struct ContinuousReaderContentView: View {
    let publication: OpenedPublication
    let initialLocator: Locator?
    let navigationRequest: ReaderNavigationRequest?
    let speechHighlightLocator: Locator?
    let preferences: ReaderPreferences
    let dynamicTypeCategory: ReaderDynamicTypeCategory
    let appearance: ReaderThemeAppearance
    let onLocationChange: (Locator) -> Void
    let onError: () -> Void

    @State private var references: [ContinuousReaderChapterReference] = []
    @State private var chapters: [String: ContinuousReaderChapter] = [:]
    @State private var loadingHREFs: Set<String> = []
    @State private var didScrollToInitialLocation = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                chapterList
                .padding(.horizontal, 34)
                .padding(.top, 70)
                .padding(.bottom, 92)
            }
            .background(Color(uiColor: appearance.backgroundColor).ignoresSafeArea())
            .onAppear {
                let loadedReferences = publication.continuousChapterReferences()
                references = loadedReferences
                loadInitialWindow(in: loadedReferences)
            }
            .onChange(of: navigationRequest) { request in
                guard let request else { return }
                scroll(to: request.href, proxy: proxy)
            }
            .onChange(of: speechHighlightLocator) { locator in
                guard let locator else { return }
                scroll(to: locator.href.string, proxy: proxy)
            }
            .onChange(of: references) { _ in
                scrollToInitialLocationIfNeeded(proxy: proxy)
            }
        }
    }

    private var chapterList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(references) { reference in
                chapterView(for: reference)
            }
        }
    }

    private func chapterView(for reference: ContinuousReaderChapterReference) -> some View {
        ContinuousReaderChapterView(
            reference: reference,
            chapter: chapters[reference.href],
            isListeningChapter: isListeningChapter(reference),
            preferences: preferences,
            dynamicTypeCategory: dynamicTypeCategory,
            appearance: appearance
        )
        .id(reference.href)
        .onAppear {
            loadWindow(around: reference.index)
            publishLocation(for: reference)
        }
    }

    private func isListeningChapter(_ reference: ContinuousReaderChapterReference) -> Bool {
        speechHighlightLocator?.href.string.resourceHREF == reference.href.resourceHREF
    }

    private func loadInitialWindow(in references: [ContinuousReaderChapterReference]) {
        let initialIndex = index(for: initialLocator?.href.string, in: references) ?? 0
        loadWindow(around: initialIndex, in: references)
    }

    private func loadWindow(around index: Int) {
        loadWindow(around: index, in: references)
    }

    private func loadWindow(around index: Int, in references: [ContinuousReaderChapterReference]) {
        guard !references.isEmpty else { return }
        let lower = max(0, index - 1)
        let upper = min(references.count - 1, index + 2)
        for reference in references[lower ... upper] {
            load(reference)
        }
    }

    private func load(_ reference: ContinuousReaderChapterReference) {
        guard chapters[reference.href] == nil, !loadingHREFs.contains(reference.href) else { return }
        loadingHREFs.insert(reference.href)
        Task {
            do {
                let chapter = try await publication.continuousChapter(for: reference)
                chapters[reference.href] = chapter
            } catch {
                onError()
            }
            loadingHREFs.remove(reference.href)
        }
    }

    private func scroll(to href: String, proxy: ScrollViewProxy) {
        let target = href.resourceHREF
        guard references.contains(where: { $0.href.resourceHREF == target }) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func scrollToInitialLocationIfNeeded(proxy: ScrollViewProxy) {
        guard !didScrollToInitialLocation else { return }
        didScrollToInitialLocation = true
        guard let href = initialLocator?.href.string.resourceHREF else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(href, anchor: .top)
        }
    }

    private func publishLocation(for reference: ContinuousReaderChapterReference) {
        guard let href = AnyURL(string: reference.href) else { return }
        let denominator = max(Double(references.count), 1)
        let locator = Locator(
            href: href,
            mediaType: .xhtml,
            title: reference.title,
            locations: .init(
                progression: 0,
                totalProgression: Double(reference.index) / denominator,
                position: reference.index + 1
            )
        )
        onLocationChange(locator)
    }

    private func index(for href: String?) -> Int? {
        index(for: href, in: references)
    }

    private func index(
        for href: String?,
        in references: [ContinuousReaderChapterReference]
    ) -> Int? {
        guard let href else { return nil }
        let target = href.resourceHREF
        return references.first { $0.href.resourceHREF == target }?.index
    }
}

private struct ContinuousReaderChapterView: View {
    @Environment(\.appStrings) private var strings
    let reference: ContinuousReaderChapterReference
    let chapter: ContinuousReaderChapter?
    let isListeningChapter: Bool
    let preferences: ReaderPreferences
    let dynamicTypeCategory: ReaderDynamicTypeCategory
    let appearance: ReaderThemeAppearance

    private var bodyFontSize: CGFloat {
        27 * preferences.effectiveFontScale(for: dynamicTypeCategory)
    }

    private var titleFontSize: CGFloat {
        bodyFontSize * 1.25
    }

    private var textColor: Color {
        appearance.backgroundColor == .black ? .white : Color(uiColor: .label)
    }

    private var secondaryTextColor: Color {
        appearance.backgroundColor == .black ? Color.white.opacity(0.72) : Color(uiColor: .secondaryLabel)
    }

    private var listeningBackground: Color {
        appearance.backgroundColor == .black ? Color.white.opacity(0.12) : Color.accentColor.opacity(0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(chapter?.title ?? reference.title)
                .font(readerFont(size: titleFontSize, weight: .bold))
                .foregroundStyle(textColor)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, reference.index == 0 ? 12 : 34)

            if let chapter {
                VStack(alignment: .leading, spacing: max(14, bodyFontSize * (preferences.lineHeight - 1))) {
                    ForEach(Array(chapter.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(readerFont(size: bodyFontSize, weight: .regular))
                            .lineSpacing(max(4, bodyFontSize * (preferences.lineHeight - 1) * 0.4))
                            .foregroundStyle(textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(strings.language == .chinese ? "正在加载正文" : "Loading text")
                    .font(readerFont(size: bodyFontSize, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, isListeningChapter ? 14 : 0)
        .background(isListeningChapter ? listeningBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func readerFont(size: CGFloat, weight: Font.Weight) -> Font {
        switch preferences.fontFamily {
        case .system:
            return .system(size: size, weight: weight)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .sans:
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

private extension DynamicTypeSize {
    var readerCategory: ReaderDynamicTypeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

private struct AccessibilityChapterHeading: UIViewRepresentable {
    let title: String
    let focusGeneration: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        ChapterHeadingLabelStyle.apply(to: label)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = title
        label.accessibilityLabel = title
        guard focusGeneration > 0,
              focusGeneration != context.coordinator.lastPostedGeneration
        else { return }
        context.coordinator.lastPostedGeneration = focusGeneration
        UIAccessibility.post(notification: .layoutChanged, argument: label)
    }

    final class Coordinator {
        var lastPostedGeneration = 0
    }
}

enum ChapterHeadingLabelStyle {
    static func apply(to label: UILabel) {
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.backgroundColor = .systemBackground.withAlphaComponent(0.92)
        label.isAccessibilityElement = true
        label.accessibilityTraits = .header
        label.accessibilityIdentifier = "reader.chapterHeading"
    }
}
