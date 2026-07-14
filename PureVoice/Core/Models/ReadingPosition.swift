struct ReadingPosition: Equatable, Sendable {
    let href: String
    let locationsJSON: String?
    let progression: Double

    init(href: String, locationsJSON: String? = nil, progression: Double) {
        self.href = href
        self.locationsJSON = locationsJSON
        self.progression = min(max(progression, 0), 1)
    }
}
