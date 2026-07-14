import Foundation

protocol ImportFileStoring: Sendable {
    func importOriginal(from sourceURL: URL, bookID: UUID) throws -> URL
    func canonicalURL(for bookID: UUID) -> URL
    func removeCanonicalFile(bookID: UUID) throws
}

extension BookFileStore: ImportFileStoring {}

actor ImportIO {
    private let fileStore: any ImportFileStoring
    private let detector: BookFormatDetector

    init(fileStore: any ImportFileStoring, detector: BookFormatDetector) {
        self.fileStore = fileStore
        self.detector = detector
    }

    func copyOriginal(from sourceURL: URL, bookID: UUID) throws -> URL {
        try fileStore.importOriginal(from: sourceURL, bookID: bookID)
    }

    func detect(at copiedFileURL: URL) throws -> BookFormat {
        try detector.detect(at: copiedFileURL)
    }

    func canonicalURL(for bookID: UUID) -> URL {
        fileStore.canonicalURL(for: bookID)
    }

    func removeCanonicalFile(bookID: UUID) throws {
        try fileStore.removeCanonicalFile(bookID: bookID)
    }
}

protocol CanonicalPublicationConverting: Sendable {
    func convert(
        originalURL: URL,
        format: BookFormat,
        suggestedTitle: String,
        destinationURL: URL
    ) async throws
}

struct PublicationMetadata: Equatable, Sendable {
    let title: String
    let author: String?
    let coverURL: URL?
}

protocol PublicationOpening: Sendable {
    func openPublication(at canonicalURL: URL) async throws -> PublicationMetadata
}

@MainActor
final class ImportCoordinator: ObservableObject {
    @Published private(set) var state: ImportState = .idle

    private let importIO: ImportIO
    private let converter: any CanonicalPublicationConverting
    private let publicationOpener: any PublicationOpening
    private let repository: any BookRepository
    private let stateObserver: @MainActor (ImportState) -> Void
    private var isImporting = false

    init(
        fileStore: any ImportFileStoring,
        detector: BookFormatDetector,
        converter: any CanonicalPublicationConverting,
        publicationOpener: any PublicationOpening,
        repository: any BookRepository,
        stateObserver: @escaping @MainActor (ImportState) -> Void = { _ in }
    ) {
        importIO = ImportIO(fileStore: fileStore, detector: detector)
        self.converter = converter
        self.publicationOpener = publicationOpener
        self.repository = repository
        self.stateObserver = stateObserver
    }

    func importBook(from sourceURL: URL) async throws {
        guard !isImporting else { throw ImportCoordinatorError.importInProgress }
        isImporting = true
        defer { isImporting = false }

        let bookID = UUID()
        let suggestedTitle = sourceURL.deletingPathExtension().lastPathComponent
        var copiedOriginalURL: URL?
        var phase = ImportPhase.copy

        do {
            try Task.checkCancellation()
            transition(to: .copying)
            let originalURL = try await importIO.copyOriginal(from: sourceURL, bookID: bookID)
            copiedOriginalURL = originalURL

            try Task.checkCancellation()
            phase = .detect
            transition(to: .detecting)
            let format = try await importIO.detect(at: originalURL)

            try Task.checkCancellation()
            phase = .convert
            transition(to: .converting(format))
            let canonicalURL = await importIO.canonicalURL(for: bookID)
            try await converter.convert(
                originalURL: originalURL,
                format: format,
                suggestedTitle: suggestedTitle,
                destinationURL: canonicalURL
            )
            try Task.checkCancellation()

            phase = .open
            transition(to: .openingPublication)
            let metadata = try await publicationOpener.openPublication(at: canonicalURL)
            try Task.checkCancellation()

            phase = .save
            let title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let author = metadata.author?.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = Book(
                id: bookID,
                title: title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : title,
                author: author.flatMap { $0.isEmpty ? nil : $0 } ?? "未知作者",
                format: format,
                originalFileURL: originalURL,
                canonicalFileURL: canonicalURL,
                coverFileURL: metadata.coverURL,
                position: nil,
                lastOpenedAt: nil,
                createdAt: Date()
            )
            try await repository.save(book)
            try Task.checkCancellation()
            transition(to: .completed(bookID))
        } catch {
            let failure = await handleFailure(
                error,
                phase: phase,
                bookID: bookID,
                hasCopiedOriginal: copiedOriginalURL != nil
            )
            transition(to: .failed(failure))
        }
    }

    private func transition(to newState: ImportState) {
        state = newState
        stateObserver(newState)
    }

    private func handleFailure(
        _ error: Error,
        phase: ImportPhase,
        bookID: UUID,
        hasCopiedOriginal: Bool
    ) async -> ImportFailure {
        if phase == .save, let rollbackFailure = await rollbackSavedBook(bookID: bookID) {
            return .saveFailed(rollbackFailure)
        }

        if hasCopiedOriginal {
            do {
                try await importIO.removeCanonicalFile(bookID: bookID)
            } catch {
                return .cleanupFailed(
                    "清理 publication.epub 失败：\((error as NSError).localizedDescription)"
                )
            }
        }
        return map(error, phase: phase)
    }

    private func rollbackSavedBook(bookID: UUID) async -> String? {
        let savedBook: Book?
        do {
            savedBook = try await repository.book(id: bookID)
        } catch {
            return "回滚失败：无法确认书籍记录状态，已保留 canonical 文件：\((error as NSError).localizedDescription)"
        }
        guard savedBook != nil else { return nil }

        do {
            try await repository.delete(id: bookID)
        } catch {
            return "回滚失败：无法删除已保存记录，已保留 canonical 文件：\((error as NSError).localizedDescription)"
        }

        do {
            guard try await repository.book(id: bookID) == nil else {
                return "回滚失败：书籍记录仍然存在，已保留 canonical 文件"
            }
        } catch {
            return "回滚失败：无法确认记录已删除，已保留 canonical 文件：\((error as NSError).localizedDescription)"
        }
        return nil
    }

    private func map(_ error: Error, phase: ImportPhase) -> ImportFailure {
        if error is CancellationError {
            return .cancelled
        }
        if let fileError = error as? BookFileError {
            switch fileError {
            case .tooLarge:
                return .tooLarge
            case .outOfSpace:
                return .outOfSpace
            case .missingExtension, .invalidExtension:
                return .copyFailed(String(describing: fileError))
            }
        }
        if case TXTConversionError.fileTooLarge = error {
            return .tooLarge
        }
        if case BookFormatDetectionError.unsupportedExtension = error {
            return .unsupported
        }
        let message = (error as NSError).localizedDescription
        switch phase {
        case .copy:
            return .copyFailed(message)
        case .detect:
            return .detectFailed(message)
        case .convert:
            return .convertFailed(message)
        case .open:
            return .openFailed(message)
        case .save:
            return .saveFailed(message)
        }
    }
}

private enum ImportPhase: Equatable {
    case copy
    case detect
    case convert
    case open
    case save
}
