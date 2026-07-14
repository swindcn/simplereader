import Foundation

enum BookFileError: Error, Equatable, Sendable {
    case missingExtension
    case invalidExtension
    case tooLarge(actualBytes: Int64, maximumBytes: Int64)
    case outOfSpace
}

final class BookFileStore: @unchecked Sendable {
    static let maximumImportSize: Int64 = 250 * 1_024 * 1_024

    let booksRoot: URL
    private let fileManager: FileManager

    convenience init(fileManager: FileManager = .default) throws {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(applicationSupportRoot: applicationSupport, fileManager: fileManager)
    }

    init(applicationSupportRoot: URL, fileManager: FileManager = .default) {
        booksRoot = applicationSupportRoot
            .appendingPathComponent("PureVoice", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
        self.fileManager = fileManager
    }

    init(booksRoot: URL, fileManager: FileManager = .default) {
        self.booksRoot = booksRoot
        self.fileManager = fileManager
    }

    func importOriginal(from sourceURL: URL, bookID: UUID) throws -> URL {
        let extensionName = try normalizedExtension(from: sourceURL)
        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let size = try fileSize(at: sourceURL)
        guard size <= Self.maximumImportSize else {
            throw BookFileError.tooLarge(
                actualBytes: size,
                maximumBytes: Self.maximumImportSize
            )
        }

        let directory = bookDirectory(for: bookID)
        let destination = directory.appendingPathComponent("original.\(extensionName)")
        let temporary = directory.appendingPathComponent(".import-\(UUID().uuidString)")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: temporary)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
            return destination
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw Self.translateFileError(error)
        }
    }

    func canonicalURL(for bookID: UUID) -> URL {
        bookDirectory(for: bookID).appendingPathComponent("publication.epub")
    }

    func coverURL(for bookID: UUID) -> URL {
        bookDirectory(for: bookID).appendingPathComponent("cover")
    }

    func deleteBookFiles(bookID: UUID) throws {
        let directory = bookDirectory(for: bookID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func bookDirectory(for bookID: UUID) -> URL {
        booksRoot.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    private func normalizedExtension(from url: URL) throws -> String {
        let value = url.pathExtension.lowercased()
        guard !value.isEmpty else { throw BookFileError.missingExtension }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted
        guard value.rangeOfCharacter(from: allowed) == nil else {
            throw BookFileError.invalidExtension
        }
        return value
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            return Int64(size)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func translateFileError(_ error: Error) -> Error {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return BookFileError.outOfSpace
        }
        return error
    }
}
