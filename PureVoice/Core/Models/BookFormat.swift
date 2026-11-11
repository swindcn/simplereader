enum BookFormat: Equatable, Sendable {
    case txt
    case epub
    case mobi
}

extension BookFormat {
    var fileExtension: String {
        switch self {
        case .txt: "txt"
        case .epub: "epub"
        case .mobi: "mobi"
        }
    }
}
