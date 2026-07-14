import Foundation

struct Chapter: Equatable, Identifiable, Sendable {
    let index: Int
    let title: String
    let body: String

    var id: Int { index }
}
