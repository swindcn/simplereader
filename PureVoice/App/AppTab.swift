enum AppTab: CaseIterable {
    case library
    case importBooks
    case settings

    var title: String {
        title(in: AppStrings(language: .chinese))
    }

    func title(in strings: AppStrings) -> String {
        switch self {
        case .library:
            return strings.libraryTab
        case .importBooks:
            return strings.importTab
        case .settings:
            return strings.settingsTab
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            return "books.vertical"
        case .importBooks:
            return "square.and.arrow.down"
        case .settings:
            return "gearshape"
        }
    }
}
