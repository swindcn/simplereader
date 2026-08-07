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
    let reportsFailure: Bool

    init(href: String, locator: Locator? = nil, reportsFailure: Bool = true) {
        self.href = href
        self.locator = locator
        self.reportsFailure = reportsFailure
    }
}

enum ReaderChapterDirection: Equatable {
    case previous
    case next
}

enum ReaderChapterNavigationOutcome: Equatable {
    case moved(title: String)
    case boundary(message: String)
    case unavailable(message: String)
}

enum PublicationReadingFilter {
    static func readableTopLevelChapters(in entries: [ReaderTOCEntry]) -> [ReaderTOCEntry] {
        entries.filter { $0.level == 0 && !isLikelyNavigationEntry(title: $0.title, href: $0.href) }
    }

    static func navigationResourceHREFs(in entries: [ReaderTOCEntry]) -> Set<String> {
        Set(
            entries
                .filter { isLikelyNavigationEntry(title: $0.title, href: $0.href) }
                .map { $0.href.resourceHREF }
        )
    }

    static func targetChapterIndex(
        for direction: ReaderChapterDirection,
        currentResource: String?,
        in chapters: [ReaderTOCEntry]
    ) -> Int? {
        guard !chapters.isEmpty else { return nil }
        let currentResource = currentResource?.resourceHREF

        if let currentResource, isLikelyNavigationResource(currentResource) {
            return direction == .next ? chapters.startIndex : nil
        }

        guard let currentIndex = currentResource.flatMap({ resource in
            chapters.lastIndex { resourceHREFsMatch($0.href, resource) }
        }) else {
            return direction == .next ? chapters.startIndex : nil
        }

        switch direction {
        case .previous:
            return currentIndex - 1
        case .next:
            return currentIndex + 1
        }
    }

    static func isLikelyNavigationResource(_ href: String) -> Bool {
        let resource = href.resourceHREF
            .removingPercentEncoding?
            .lowercased()
            ?? href.resourceHREF.lowercased()
        let filename = resource.split(separator: "/").last.map(String.init) ?? resource
        let basename = filename.split(separator: ".").first.map(String.init) ?? filename
        return ["nav", "toc", "contents", "table-of-contents"].contains(basename)
    }

    static func isLikelyNavigationEntry(title: String?, href: String) -> Bool {
        isLikelyNavigationResource(href) || isLikelyNavigationTitle(title)
    }

    static func resourceHREFsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = normalizedResourceHREF(lhs)
        let rhs = normalizedResourceHREF(rhs)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs
            || lhs.hasSuffix("/\(rhs)")
            || rhs.hasSuffix("/\(lhs)")
    }

    private static func isLikelyNavigationTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }

        return ["目录", "目錄", "toc", "contents", "tableofcontents"].contains(normalized)
    }

    private static func normalizedResourceHREF(_ href: String) -> String {
        let decoded = href.resourceHREF.removingPercentEncoding ?? href.resourceHREF
        return decoded
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
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
    @Published private(set) var speechHighlightLocator: Locator?
    @Published private(set) var errorMessage: String?

    var isReady: Bool { openedPublication != nil && !isLoading }
    var bookID: UUID { book.id }

    private let repository: any BookRepository
    private let publicationService: PublicationService
    private let appStateRestorer: AppStateRestorer?
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
        appStateRestorer: AppStateRestorer? = nil,
        persistenceDelay: TimeInterval = 1
    ) {
        self.book = book
        self.repository = repository
        self.publicationService = publicationService
        self.appStateRestorer = appStateRestorer
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
            errorMessage = UserFacingError.readerOpenFailure(error).message
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
        currentLocator = locator
        updateChapter(for: locator.href.string)
        navigationRequest = ReaderNavigationRequest(href: locator.href.string, locator: locator)
    }

    func followListening(at locator: Locator) {
        guard openedPublication?.readiumPublication.linkWithHREF(locator.href) != nil else {
            clearSpeechHighlight()
            return
        }
        currentLocator = locator
        updateChapter(for: locator.href.string)
        speechHighlightLocator = locator
        navigationRequest = ReaderNavigationRequest(
            href: locator.href.string,
            locator: locator,
            reportsFailure: false
        )
    }

    func clearSpeechHighlight() {
        speechHighlightLocator = nil
    }

    func navigateAdjacentChapter(_ direction: ReaderChapterDirection) -> ReaderChapterNavigationOutcome {
        let chapters = PublicationReadingFilter.readableTopLevelChapters(in: tableOfContents)
        guard !chapters.isEmpty else {
            return .unavailable(message: "没有可用章节")
        }

        let currentResource = (currentLocator?.href.string ?? initialLocator?.href.string)?.resourceHREF
        let boundaryMessage: String

        switch direction {
        case .previous:
            boundaryMessage = "已经是第一章"
        case .next:
            boundaryMessage = "已经是最后一章"
        }

        guard let targetIndex = PublicationReadingFilter.targetChapterIndex(
            for: direction,
            currentResource: currentResource,
            in: chapters
        ) else {
            return .boundary(message: boundaryMessage)
        }
        guard chapters.indices.contains(targetIndex) else {
            return .boundary(message: boundaryMessage)
        }

        let entry = chapters[targetIndex]
        navigationRequest = ReaderNavigationRequest(href: entry.href)
        currentLocator = Locator(
            href: AnyURL(string: entry.href)!,
            mediaType: .xhtml,
            title: entry.title,
            locations: .init(progression: 0)
        )
        updateChapter(for: entry.href)
        return .moved(title: entry.title)
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
                appStateRestorer?.recordReading(bookID: book.id, position: position)
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
}
