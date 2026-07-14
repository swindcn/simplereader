enum ImportState: Equatable, Sendable {
    case idle
    case copying
    case detecting
    case converting(BookFormat)
    case openingPublication
    case completed(Book.ID)
    case failed(ImportFailure)
}
