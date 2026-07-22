import SwiftUI
import UIKit
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

struct EPUBScrollAutoAdvancePolicy {
    var bottomThreshold: CGFloat = 96
    var cooldown: TimeInterval = 1.2
    private var lastAdvanceTime: TimeInterval?

    init(bottomThreshold: CGFloat = 96, cooldown: TimeInterval = 1.2) {
        self.bottomThreshold = bottomThreshold
        self.cooldown = cooldown
    }

    mutating func shouldAdvance(
        isScrollLayout: Bool,
        isVoiceOverRunning: Bool,
        isUserScrolling: Bool,
        contentOffsetY: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        now: TimeInterval
    ) -> Bool {
        guard isScrollLayout,
              !isVoiceOverRunning,
              isUserScrolling,
              viewportHeight > 0,
              contentHeight > viewportHeight + bottomThreshold
        else { return false }

        if let lastAdvanceTime, now - lastAdvanceTime < cooldown {
            return false
        }

        let remaining = contentHeight - viewportHeight - max(contentOffsetY, 0)
        guard remaining <= bottomThreshold else { return false }
        lastAdvanceTime = now
        return true
    }
}

struct PreferenceSubmissionDecision<Value: Equatable> {
    private var lastValue: Value?

    init(initialValue: Value? = nil) {
        lastValue = initialValue
    }

    mutating func shouldSubmit(_ value: Value) -> Bool {
        guard lastValue != value else { return false }
        lastValue = value
        return true
    }
}

@MainActor
final class EPUBNavigatorCommands: ObservableObject {
    fileprivate weak var navigator: EPUBNavigatorViewController?

    func previousPage() {
        Task { await navigator?.goBackward() }
    }

    func nextPage() {
        Task { await navigator?.goForward() }
    }
}

struct EPUBNavigatorController: UIViewControllerRepresentable {
    let publication: OpenedPublication
    let initialLocation: Locator?
    let preferences: EPUBPreferences
    let navigationRequest: ReaderNavigationRequest?
    let speechHighlightLocator: Locator?
    let commands: EPUBNavigatorCommands
    let onLocationChange: (Locator) -> Void
    let onNavigationFailure: () -> Void
    let onError: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLocationChange: onLocationChange,
            onNavigationFailure: onNavigationFailure,
            onError: onError
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication.readiumPublication,
                initialLocation: initialLocation,
                config: .init(
                    preferences: preferences,
                    disablePageTurnsWhileScrolling: true
                )
            )
            navigator.delegate = context.coordinator
            context.coordinator.navigator = navigator
            context.coordinator.isScrollLayout = preferences.scroll == true
            context.coordinator.preferencesDecision = .init(initialValue: preferences)
            commands.navigator = navigator
            let coordinator = context.coordinator
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                coordinator.refreshScrollObservers(in: navigator.view)
            }
            return navigator
        } catch {
            Task { @MainActor in onError() }
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if context.coordinator.preferencesDecision.shouldSubmit(preferences) {
            context.coordinator.navigator?.submitPreferences(preferences)
        }
        context.coordinator.isScrollLayout = preferences.scroll == true
        context.coordinator.refreshScrollObservers(in: uiViewController.view)
        context.coordinator.applySpeechHighlight(locator: speechHighlightLocator)
        guard let request = navigationRequest,
              request.id != context.coordinator.lastNavigationRequestID,
              let navigator = context.coordinator.navigator
        else { return }
        context.coordinator.lastNavigationRequestID = request.id

        if let locator = request.locator {
            Task {
                if !(await navigator.go(to: locator)), request.reportsFailure {
                    onNavigationFailure()
                }
            }
            return
        }

        guard let href = AnyURL(string: request.href),
              let link = publication.readiumPublication.linkWithHREF(href)
        else {
            if request.reportsFailure {
                onNavigationFailure()
            }
            return
        }
        Task {
            if !(await navigator.go(to: link)), request.reportsFailure {
                onNavigationFailure()
            }
        }
    }

    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        weak var navigator: EPUBNavigatorViewController?
        var lastNavigationRequestID: UUID?
        var preferencesDecision = PreferenceSubmissionDecision<EPUBPreferences>()
        var isScrollLayout = false
        private var lastSpeechHighlightLocator: Locator?
        private var observedScrollViews: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private var autoAdvancePolicy = EPUBScrollAutoAdvancePolicy()
        private var isAutoAdvancing = false
        private let onLocationChange: (Locator) -> Void
        private let onNavigationFailure: () -> Void
        private let onError: () -> Void

        init(
            onLocationChange: @escaping (Locator) -> Void,
            onNavigationFailure: @escaping () -> Void,
            onError: @escaping () -> Void
        ) {
            self.onLocationChange = onLocationChange
            self.onNavigationFailure = onNavigationFailure
            self.onError = onError
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            onLocationChange(locator)
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            onError()
        }

        func refreshScrollObservers(in view: UIView) {
            let scrollViews = view.descendantScrollViews()
                .filter { $0.contentSize.height > 0 || !$0.bounds.isEmpty }
            let currentIDs = Set(scrollViews.map(ObjectIdentifier.init))
            observedScrollViews = observedScrollViews.filter { currentIDs.contains($0.key) }

            for scrollView in scrollViews {
                let id = ObjectIdentifier(scrollView)
                guard observedScrollViews[id] == nil else { continue }
                observedScrollViews[id] = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
                    Task { @MainActor in
                        guard let self, let scrollView else { return }
                        self.handleScrollOffsetChange(scrollView)
                    }
                }
            }
        }

        private func handleScrollOffsetChange(_ scrollView: UIScrollView) {
            guard let navigator, !isAutoAdvancing else { return }
            let userScrolling = scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
            guard autoAdvancePolicy.shouldAdvance(
                isScrollLayout: isScrollLayout,
                isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
                isUserScrolling: userScrolling,
                contentOffsetY: scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
                viewportHeight: scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom,
                contentHeight: scrollView.contentSize.height,
                now: ProcessInfo.processInfo.systemUptime
            ) else { return }

            isAutoAdvancing = true
            Task {
                _ = await navigator.goForward(options: NavigatorGoOptions(animated: false))
                await MainActor.run { self.isAutoAdvancing = false }
            }
        }

        func applySpeechHighlight(locator: Locator?) {
            guard locator != lastSpeechHighlightLocator else { return }
            lastSpeechHighlightLocator = locator
            let decorations = locator.map {
                [
                    Decoration(
                        id: "current-speech",
                        locator: $0,
                        style: .highlight(tint: UIColor.systemYellow, isActive: true)
                    )
                ]
            } ?? []
            navigator?.apply(decorations: decorations, in: "tts")
        }
    }
}

private extension UIView {
    func descendantScrollViews() -> [UIScrollView] {
        var result: [UIScrollView] = []
        if let scrollView = self as? UIScrollView {
            result.append(scrollView)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendantScrollViews())
        }
        return result
    }
}

extension ReaderPreferences {
    func epubPreferences(
        dynamicTypeCategory: ReaderDynamicTypeCategory,
        usesDarkSystemTheme: Bool
    ) -> EPUBPreferences {
        let readiumFont: FontFamily? = switch fontFamily {
        case .system: nil
        case .serif: .serif
        case .sans: .sansSerif
        }
        let readiumTheme: Theme = switch theme {
        case .system: usesDarkSystemTheme ? .dark : .light
        case .light: .light
        case .sepia: .sepia
        case .dark: .dark
        }
        return EPUBPreferences(
            columnCount: .one,
            fontFamily: readiumFont,
            fontSize: effectiveFontScale(for: dynamicTypeCategory),
            lineHeight: lineHeight,
            publisherStyles: false,
            scroll: layout == .scroll,
            spread: .never,
            textNormalization: true,
            theme: readiumTheme,
            verticalText: false
        )
    }
}
