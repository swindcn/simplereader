import SwiftUI
import UIKit
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

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
                config: .init(preferences: ReaderEPUBPreferencesStore().load())
            )
            navigator.delegate = context.coordinator
            context.coordinator.navigator = navigator
            commands.navigator = navigator
            return navigator
        } catch {
            Task { @MainActor in onError() }
            return UIViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
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

struct ReaderEPUBPreferencesStore {
    private let defaults: UserDefaults
    private let prefix = "reader.epub.preferences."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EPUBPreferences {
        let fontSize = defaults.object(forKey: prefix + "fontSize") as? Double ?? 1.0
        let lineHeight = defaults.object(forKey: prefix + "lineHeight") as? Double ?? 1.5
        let scroll = defaults.object(forKey: prefix + "scroll") as? Bool ?? false
        let theme = defaults.string(forKey: prefix + "theme").flatMap(Theme.init(rawValue:)) ?? .light
        return EPUBPreferences(
            columnCount: .one,
            fontSize: fontSize,
            lineHeight: lineHeight,
            publisherStyles: false,
            scroll: scroll,
            spread: .never,
            textNormalization: true,
            theme: theme
        )
    }

    func save(_ preferences: EPUBPreferences) {
        set(preferences.fontSize, forKey: "fontSize")
        set(preferences.lineHeight, forKey: "lineHeight")
        set(preferences.scroll, forKey: "scroll")
        set(preferences.theme?.rawValue, forKey: "theme")
    }

    private func set(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
    }
}
