import SwiftUI
import UIKit
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

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
                config: .init(preferences: preferences)
            )
            navigator.delegate = context.coordinator
            context.coordinator.navigator = navigator
            context.coordinator.preferencesDecision = .init(initialValue: preferences)
            commands.navigator = navigator
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
        guard let request = navigationRequest,
              request.id != context.coordinator.lastNavigationRequestID,
              let navigator = context.coordinator.navigator
        else { return }
        context.coordinator.lastNavigationRequestID = request.id

        if let locator = request.locator {
            Task {
                if !(await navigator.go(to: locator)) {
                    onNavigationFailure()
                }
            }
            return
        }

        guard let href = AnyURL(string: request.href),
              let link = publication.readiumPublication.linkWithHREF(href)
        else {
            onNavigationFailure()
            return
        }
        Task {
            if !(await navigator.go(to: link)) {
                onNavigationFailure()
            }
        }
    }

    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        weak var navigator: EPUBNavigatorViewController?
        var lastNavigationRequestID: UUID?
        var preferencesDecision = PreferenceSubmissionDecision<EPUBPreferences>()
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
            theme: readiumTheme
        )
    }
}
