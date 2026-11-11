import Foundation

@MainActor
struct BundledBookInstaller {
    static let installedDefaultsKey = "BundledBookInstaller.didInstallReviewBook.v1"

    let repository: any BookRepository
    let defaults: UserDefaults
    let sourceURL: () -> URL?
    let importBook: (URL) async throws -> Void

    init(
        repository: any BookRepository,
        defaults: UserDefaults = .standard,
        sourceURL: @escaping () -> URL?,
        importBook: @escaping (URL) async throws -> Void
    ) {
        self.repository = repository
        self.defaults = defaults
        self.sourceURL = sourceURL
        self.importBook = importBook
    }

    func installIfNeeded() async throws {
        guard !defaults.bool(forKey: Self.installedDefaultsKey) else { return }

        let existingBooks = try await repository.allBooks()
        guard existingBooks.isEmpty else {
            defaults.set(true, forKey: Self.installedDefaultsKey)
            return
        }

        guard let bundledBookURL = sourceURL() else { return }
        try await importBook(bundledBookURL)
        defaults.set(true, forKey: Self.installedDefaultsKey)
    }
}
