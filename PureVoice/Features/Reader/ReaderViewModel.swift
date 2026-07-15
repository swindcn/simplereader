import Foundation
@preconcurrency import ReadiumShared

struct ReaderTOCEntry: Equatable, Identifiable {
    let id: String
    let title: String
    let href: String
    let level: Int
}

struct ReaderNavigationRequest: Equatable, Identifiable {
    let id = UUID()
    let href: String
    let locator: Locator?

    init(href: String, locator: Locator? = nil) {
        self.href = href
        self.locator = locator
    }
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

    var isReady: Bool { openedPublication != nil && !isLoading }

    private let repository: any BookRepository
    private let publicationService: PublicationService
    private let persistenceDelay: TimeInterval
    private var book: Book
    private var pendingPosition: ReadingPosition?
    private var persistenceTask: Task<Void, Never>?
    private var isPersisting = false
    private var persistenceWaiters: [CheckedContinuation<Bool, Never>] = []
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

        let publication: OpenedPublication
        do {
            publication = try await publicationService.open(at: book.canonicalFileURL)
        } catch {
            errorMessage = Self.message(for: error)
            isLoading = false
            return
        }

        if let position = book.position {
            do {
                let locator = try await publication.locator(from: position)
                publish(publication, initialLocator: locator)
            } catch {
                book.position = nil
                publish(
                    publication,
                    initialLocator: nil,
                    warning: "上次阅读位置已失效，已从书首开始。"
                )
            }
        } else {
            publish(publication, initialLocator: nil)
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

    func returnFromListening(at locator: Locator) {
        guard openedPublication?.readiumPublication.linkWithHREF(locator.href) != nil else {
            errorMessage = "无法返回到当前听书位置。"
            return
        }
        navigationRequest = ReaderNavigationRequest(href: locator.href.string, locator: locator)
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

    @discardableResult
    func flushProgress() async -> Bool {
        persistenceTask?.cancel()
        persistenceTask = nil

        if isPersisting {
            return await withCheckedContinuation { continuation in
                persistenceWaiters.append(continuation)
            }
        }

        guard pendingPosition != nil else { return true }
        isPersisting = true
        let succeeded = await drainPendingProgress()
        isPersisting = false

        let waiters = persistenceWaiters
        persistenceWaiters.removeAll()
        waiters.forEach { $0.resume(returning: succeeded) }
        return succeeded
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
            await self?.flushScheduledProgress()
        }
    }

    private func flushScheduledProgress() async {
        persistenceTask = nil
        await flushProgress()
    }

    private func drainPendingProgress() async -> Bool {
        while let position = pendingPosition {
            persistenceTask?.cancel()
            persistenceTask = nil
            pendingPosition = nil

            do {
                try await repository.updatePosition(id: book.id, position: position)
                book.position = position
            } catch {
                if pendingPosition == nil {
                    pendingPosition = position
                }
                errorMessage = "无法保存阅读进度。"
                return false
            }
        }
        return true
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

    static func flatten(
        _ items: [PublicationTOCItem],
        level: Int = 0,
        parentPath: [Int] = []
    ) -> [ReaderTOCEntry] {
        items.enumerated().flatMap { index, item in
            let path = parentPath + [index]
            return [ReaderTOCEntry(
                id: path.map(String.init).joined(separator: "."),
                title: item.title,
                href: item.href,
                level: level
            )] + flatten(item.children, level: level + 1, parentPath: path)
        }
    }

    private func publish(
        _ publication: OpenedPublication,
        initialLocator: Locator?,
        warning: String? = nil
    ) {
        openedPublication = publication
        self.initialLocator = initialLocator
        currentLocator = initialLocator
        tableOfContents = Self.flatten(publication.tableOfContents)
        updateChapter(for: initialLocator?.href.string ?? publication.tableOfContents.first?.href)
        errorMessage = warning
        isLoading = false
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "无法打开这本书。"
    }
}
