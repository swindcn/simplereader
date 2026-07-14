import Foundation

enum BookFileError: Error, Equatable, Sendable {
    case missingExtension
    case invalidExtension
    case tooLarge(actualBytes: Int64, maximumBytes: Int64)
    case outOfSpace
}

enum BookFileTransactionOperation: Equatable, Sendable {
    case installStagedDirectory
    case removeCommittedBackup
    case removeBookArtifact(String)
}

final class BookFileStore: @unchecked Sendable {
    static let maximumImportSize: Int64 = 250 * 1_024 * 1_024

    let booksRoot: URL
    private let fileManager: FileManager
    private let transactionHook: (BookFileTransactionOperation) throws -> Void

    convenience init(fileManager: FileManager = .default) throws {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(applicationSupportRoot: applicationSupport, fileManager: fileManager)
    }

    init(
        applicationSupportRoot: URL,
        fileManager: FileManager = .default,
        transactionHook: @escaping (BookFileTransactionOperation) throws -> Void = { _ in }
    ) {
        booksRoot = applicationSupportRoot
            .appendingPathComponent("PureVoice", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
        self.fileManager = fileManager
        self.transactionHook = transactionHook
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
        let transactionID = UUID().uuidString
        let staging = transactionDirectory(for: bookID, kind: "staging", id: transactionID)
        let backup = transactionDirectory(for: bookID, kind: "backup", id: transactionID)
        let stagedDestination = staging.appendingPathComponent("original.\(extensionName)")
        let destination = directory.appendingPathComponent("original.\(extensionName)")

        do {
            try fileManager.createDirectory(at: booksRoot, withIntermediateDirectories: true)
            try recoverInterruptedTransaction(for: bookID)
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.copyItem(at: directory, to: staging)
            } else {
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            }
            try removeOriginals(in: staging)
            try fileManager.copyItem(at: sourceURL, to: stagedDestination)
            try commit(
                staging: staging,
                backup: backup,
                directory: directory
            )
            return destination
        } catch {
            removeIfPresent(staging)
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
        guard fileManager.fileExists(atPath: booksRoot.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: booksRoot,
            includingPropertiesForKeys: nil
        )
        var targets = contents.filter { isTransactionArtifact($0, for: bookID) }
        if fileManager.fileExists(atPath: directory.path) {
            targets.insert(directory, at: 0)
        }

        var firstError: Error?
        for target in targets {
            do {
                try transactionHook(.removeBookArtifact(target.lastPathComponent))
                try fileManager.removeItem(at: target)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func bookDirectory(for bookID: UUID) -> URL {
        booksRoot.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    private func normalizedExtension(from url: URL) throws -> String {
        let value = url.pathExtension.lowercased()
        guard !value.isEmpty else { throw BookFileError.missingExtension }
        guard isSafeExtension(value) else {
            throw BookFileError.invalidExtension
        }
        return value
    }

    private func removeOriginals(in directory: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for candidate in contents where isOriginalFile(candidate) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private func commit(staging: URL, backup: URL, directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            do {
                try transactionHook(.installStagedDirectory)
                try fileManager.moveItem(at: staging, to: directory)
            } catch {
                removeIfPresent(directory)
                throw error
            }
            return
        }

        try fileManager.moveItem(at: directory, to: backup)
        do {
            try transactionHook(.installStagedDirectory)
            try fileManager.moveItem(at: staging, to: directory)
        } catch {
            let commitError = error
            removeIfPresent(directory)
            try fileManager.moveItem(at: backup, to: directory)
            removeIfPresent(staging)
            throw commitError
        }

        do {
            try transactionHook(.removeCommittedBackup)
            try fileManager.removeItem(at: backup)
        } catch {
            // The official directory is committed. The next import reclaims this backup.
        }
    }

    private func recoverInterruptedTransaction(for bookID: UUID) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: booksRoot,
            includingPropertiesForKeys: nil
        )
        let stagingDirectories = contents.filter {
            isTransactionArtifact($0, for: bookID, kind: "staging")
        }
        let backupDirectories = contents.filter {
            isTransactionArtifact($0, for: bookID, kind: "backup")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let directory = bookDirectory(for: bookID)

        if !fileManager.fileExists(atPath: directory.path), let backup = backupDirectories.first {
            try fileManager.moveItem(at: backup, to: directory)
        }
        for transactionDirectory in stagingDirectories + backupDirectories {
            removeIfPresent(transactionDirectory)
        }
    }

    private func transactionDirectory(
        for bookID: UUID,
        kind: String,
        id: String
    ) -> URL {
        booksRoot.appendingPathComponent(
            ".\(bookID.uuidString).\(kind)-\(id)",
            isDirectory: true
        )
    }

    private func isTransactionArtifact(
        _ url: URL,
        for bookID: UUID,
        kind requestedKind: String? = nil
    ) -> Bool {
        let name = url.lastPathComponent
        let kinds = requestedKind.map { [$0] } ?? ["staging", "backup"]
        for kind in kinds {
            let prefix = ".\(bookID.uuidString).\(kind)-"
            guard name.hasPrefix(prefix) else { continue }
            let transactionID = String(name.dropFirst(prefix.count))
            guard let uuid = UUID(uuidString: transactionID) else { return false }
            return uuid.uuidString == transactionID
        }
        return false
    }

    private func removeIfPresent(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func isOriginalFile(_ url: URL) -> Bool {
        let extensionName = url.pathExtension
        return !extensionName.isEmpty
            && url.deletingPathExtension().lastPathComponent == "original"
            && isSafeExtension(extensionName)
    }

    private func isSafeExtension(_ value: String) -> Bool {
        let disallowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
            .inverted
        return value.rangeOfCharacter(from: disallowed) == nil
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
