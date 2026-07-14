import Foundation

protocol ImportFileStoring: Sendable {
    func importOriginal(from sourceURL: URL, bookID: UUID) throws -> URL
    func canonicalURL(for bookID: UUID) -> URL
    func removeCanonicalFile(bookID: UUID) throws
}

extension BookFileStore: ImportFileStoring {}

protocol CanonicalPublicationConverting: Sendable {
    func convert(
        originalURL: URL,
        format: BookFormat,
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

    private let fileStore: any ImportFileStoring
    private let detector: BookFormatDetector
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
        self.fileStore = fileStore
        self.detector = detector
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
        var copiedOriginalURL: URL?
        var phase = ImportPhase.copy

        do {
            try Task.checkCancellation()
            transition(to: .copying)
            let originalURL = try fileStore.importOriginal(from: sourceURL, bookID: bookID)
            copiedOriginalURL = originalURL

            try Task.checkCancellation()
            phase = .detect
            transition(to: .detecting)
            let format = try detector.detect(at: originalURL)

            try Task.checkCancellation()
            phase = .convert
            transition(to: .converting(format))
            let canonicalURL = fileStore.canonicalURL(for: bookID)
            try await converter.convert(
                originalURL: originalURL,
                format: format,
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
            do {
                try Task.checkCancellation()
            } catch is CancellationError {
                do {
                    try await repository.delete(id: bookID)
                } catch {
                    throw ImportPipelineError.rollbackFailed(
                        (error as NSError).localizedDescription
                    )
                }
                throw CancellationError()
            }
            transition(to: .completed(bookID))
        } catch {
            if copiedOriginalURL != nil {
                try? fileStore.removeCanonicalFile(bookID: bookID)
            }
            transition(to: .failed(map(error, phase: phase)))
        }
    }

    private func transition(to newState: ImportState) {
        state = newState
        stateObserver(newState)
    }

    private func map(_ error: Error, phase: ImportPhase) -> ImportFailure {
        if case let ImportPipelineError.rollbackFailed(message) = error {
            return .saveFailed("取消导入后回滚失败：\(message)")
        }
        if error is CancellationError || Task.isCancelled {
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

private enum ImportPhase {
    case copy
    case detect
    case convert
    case open
    case save
}

private enum ImportPipelineError: Error {
    case rollbackFailed(String)
}
