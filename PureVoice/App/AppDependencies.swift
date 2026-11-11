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
    let webTransferViewModel: WebTransferViewModel
    let transferIdentityStore: any TransferIdentityStoring
    let serverGrantEntitlementProvider: any ServerGrantEntitlementProviding
    let libraryRefresh: LibraryRefreshSignal
    let appStateRestorer: AppStateRestorer

    static func makeProduction() async throws -> AppDependencies {
        let persistence = try await PersistenceController()
        let fileStore = try BookFileStore()
        let dependencies = production(persistence: persistence, fileStore: fileStore)
        await dependencies.installBundledReviewBookIfNeeded()
        return dependencies
    }

    static func production(
        persistence: PersistenceController,
        fileStore: BookFileStore
    ) -> AppDependencies {
        let repository = PathRelocatingBookRepository(
            base: CoreDataBookRepository(container: persistence.container),
            fileStore: fileStore
        )
        return make(repository: repository, fileStore: fileStore)
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
        let transferBaseURLString = ProcessInfo.processInfo.environment["PUREVOICE_WEB_TRANSFER_BASE_URL"] ?? ""
        let transferBaseURL = URL(string: transferBaseURLString)
            ?? URL(string: "https://nzksxspznpkquybprqms.supabase.co/functions/v1/transfer")!
        let transferPageURLString = ProcessInfo.processInfo.environment["PUREVOICE_WEB_TRANSFER_PAGE_URL"] ?? ""
        let transferPageURL = URL(string: transferPageURLString)
            ?? URL(string: "https://www.wildgrassx.com/transfer")!
        let transferIdentityStore = KeychainTransferIdentityStore()
        let webTransferViewModel = WebTransferViewModel(
            identityStore: transferIdentityStore,
            client: URLSessionWebTransferClient(baseURL: transferBaseURL),
            importCoordinator: ImportCoordinatorTransferImporter(coordinator: coordinator),
            webTransferPageURL: transferPageURL
        )
        return AppDependencies(
            repository: repository,
            importCoordinator: coordinator,
            webTransferViewModel: webTransferViewModel,
            transferIdentityStore: transferIdentityStore,
            serverGrantEntitlementProvider: URLSessionServerGrantEntitlementProvider(baseURL: transferBaseURL),
            libraryRefresh: libraryRefresh,
            appStateRestorer: appStateRestorer
        )
    }

    func installBundledReviewBookIfNeeded(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) async {
        let installer = BundledBookInstaller(
            repository: repository,
            defaults: defaults,
            sourceURL: {
                bundle.url(forResource: "pg79182-images-3", withExtension: "epub")
            },
            importBook: { url in
                try await importCoordinator.importBook(from: url)
            }
        )
        try? await installer.installIfNeeded()
    }
}
