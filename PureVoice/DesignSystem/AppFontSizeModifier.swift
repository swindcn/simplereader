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
            nil
        }
    }
}

extension View {
    @ViewBuilder
    func appFontSize(_ size: AppFontSize) -> some View {
        if let dynamicTypeSize = size.dynamicTypeSize {
            self.dynamicTypeSize(dynamicTypeSize)
        } else {
            self
        }
    }
}
