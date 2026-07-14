enum AppTab: CaseIterable {
    case library
    case importBooks
    case settings

    var title: String {
        switch self {
        case .library:
            return "书架"
        case .importBooks:
            return "导入"
        case .settings:
            return "设置"
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
