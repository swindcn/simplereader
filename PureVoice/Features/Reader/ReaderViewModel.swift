import Foundation
@preconcurrency import ReadiumShared

struct ReaderTOCEntry: Equatable, Identifiable {
    let title: String
    let href: String
    let level: Int

    var id: String { "\(level):\(href)" }
}

struct ReaderNavigationRequest: Equatable, Identifiable {
    let id = UUID()
    let href: String
}

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var openedPublication: OpenedPublication?
    @Published private(set) var initialLocator: Locator?
    @Published private(set) var currentLocator: Locator?
    @Published private(set) var chapterTitle = ""
    @Published private(set) var chapterFocusGeneration = 0
    @Published private(set) var tableOfContents: [ReaderTOCEntry] = []
    @Published var isTableOfContentsPresented = false
    @Published private(set) var navigationRequest: ReaderNavigationRequest?
    @Published private(set) var errorMessage: String?

    var isReady: Bool { openedPublication != nil && !isLoading && errorMessage == nil }

    private let repository: any BookRepository
    private let publicationService: PublicationService
    private let persistenceDelay: TimeInterval
    private var book: Book
    private var pendingPosition: ReadingPosition?
    private var persistenceTask: Task<Void, Never>?
    private var hasOpened = false

    init(
        book: Book,
        repository: any BookRepository,
        publicationService: PublicationService = PublicationService(),
        persistenceDelay: TimeInterval = 1
    ) {
        self.book = book
        self.repository = repository
        self.publicationService = publicationService
        self.persistenceDelay = persistenceDelay
    }

    func open() async {
        guard !hasOpened else { return }
        hasOpened = true
        isLoading = true
        errorMessage = nil

        do {
            let publication = try await publicationService.open(at: book.canonicalFileURL)
            let restoredLocator: Locator?
            if let position = book.position {
                restoredLocator = try await publication.locator(from: position)
            } else {
                restoredLocator = nil
            }

            openedPublication = publication
            initialLocator = restoredLocator
            currentLocator = restoredLocator
            tableOfContents = Self.flatten(publication.tableOfContents)
            updateChapter(for: restoredLocator?.href.string ?? publication.tableOfContents.first?.href)
        } catch {
            errorMessage = Self.message(for: error)
        }
        isLoading = false
    }

    func receive(locator: Locator) {
        guard let publication = openedPublication else { return }
        currentLocator = locator
        updateChapter(for: locator.href.string)

        do {
            pendingPosition = try publication.readingPosition(from: locator)
            schedulePersistence()
        } catch {
            errorMessage = "无法保存阅读进度。"
        }
    }

    func selectChapter(_ entry: ReaderTOCEntry) {
        guard let href = AnyURL(string: entry.href),
              openedPublication?.readiumPublication.linkWithHREF(href) != nil
        else {
            errorMessage = "无法打开所选章节。"
            return
        }
        navigationRequest = ReaderNavigationRequest(href: entry.href)
        isTableOfContentsPresented = false
    }

    func reportNavigationFailure() {
        errorMessage = "无法定位到所选章节。"
    }

    func reportNavigatorError() {
        errorMessage = "阅读器无法显示当前内容。"
    }

    func dismissError() {
        errorMessage = nil
    }

    func flushProgress() async {
        persistenceTask?.cancel()
        persistenceTask = nil
        guard let position = pendingPosition else { return }
        pendingPosition = nil
        book.position = position
        do {
            try await repository.save(book)
        } catch {
            pendingPosition = position
            errorMessage = "无法保存阅读进度。"
        }
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, persistenceDelay] in
            do {
                let nanoseconds = UInt64(max(persistenceDelay, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flushProgress()
        }
    }

    private func updateChapter(for href: String?) {
        guard let href,
              let title = Self.chapterTitle(containing: href, in: tableOfContents),
              title != chapterTitle
        else { return }
        chapterTitle = title
        chapterFocusGeneration += 1
    }

    private static func chapterTitle(containing href: String, in entries: [ReaderTOCEntry]) -> String? {
        let resource = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        return entries.last { entry in
            let entryResource = entry.href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? entry.href
            return entryResource == resource && !entry.href.contains("#")
        }?.title ?? entries.first { entry in
            entry.href.split(separator: "#", maxSplits: 1).first.map(String.init) == resource
        }?.title
    }

    private static func flatten(_ items: [PublicationTOCItem], level: Int = 0) -> [ReaderTOCEntry] {
        items.flatMap { item in
            [ReaderTOCEntry(title: item.title, href: item.href, level: level)]
                + flatten(item.children, level: level + 1)
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "无法打开这本书。"
    }
}
