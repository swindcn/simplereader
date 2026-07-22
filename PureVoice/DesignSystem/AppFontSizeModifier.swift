import SwiftUI

extension AppFontSize {
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .small:
            .medium
        case .medium:
            .large
        case .large:
            .xLarge
        case .extraLarge:
            .xxLarge
        }
    }
}

private struct AppFontSizeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppFontSize = .extraLarge
}

extension EnvironmentValues {
    var appFontSize: AppFontSize {
        get { self[AppFontSizeEnvironmentKey.self] }
        set { self[AppFontSizeEnvironmentKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func appFontSize(_ size: AppFontSize) -> some View {
        if let dynamicTypeSize = size.dynamicTypeSize {
            self
                .environment(\.appFontSize, size)
                .dynamicTypeSize(dynamicTypeSize)
        } else {
            self.environment(\.appFontSize, size)
        }
    }
}
