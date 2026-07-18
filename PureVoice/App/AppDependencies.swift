import Foundation

@MainActor
final class LibraryRefreshSignal: ObservableObject {
    @Published private(set) var generation = 0

    func refresh() {
        generation += 1
    }
}

@MainActor
struct AppDependencies {
    let repository: any BookRepository
    let importCoordinator: ImportCoordinator
    let libraryRefresh: LibraryRefreshSignal
    let appStateRestorer: AppStateRestorer

    static func makeProduction() async throws -> AppDependencies {
        let persistence = try await PersistenceController()
        let fileStore = try BookFileStore()
        return production(persistence: persistence, fileStore: fileStore)
    }

    static func production(
        persistence: PersistenceController,
        fileStore: BookFileStore
    ) -> AppDependencies {
        make(repository: CoreDataBookRepository(container: persistence.container), fileStore: fileStore)
    }

    static func make(
        repository: any BookRepository,
        fileStore: BookFileStore,
        converter: any CanonicalPublicationConverting = ImportPipelineConverter(),
        publicationOpener: any PublicationOpening = PublicationService(),
        appStateRestorer: AppStateRestorer = AppStateRestorer()
    ) -> AppDependencies {
        let libraryRefresh = LibraryRefreshSignal()
        let coordinator = ImportCoordinator(
            fileStore: fileStore,
            detector: BookFormatDetector(),
            converter: converter,
            publicationOpener: publicationOpener,
            repository: repository,
            stateObserver: { state in
                if case .completed = state {
                    libraryRefresh.refresh()
                }
            },
            importRecoveryRecorder: { bookID, originalFileURL, state in
                appStateRestorer.recordImport(bookID: bookID, originalFileURL: originalFileURL, state: state)
            }
        )
        return AppDependencies(
            repository: repository,
            importCoordinator: coordinator,
            libraryRefresh: libraryRefresh,
            appStateRestorer: appStateRestorer
        )
    }
}
