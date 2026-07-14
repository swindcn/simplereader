import Darwin
import XCTest
@testable import PureVoice

final class BookFileStoreTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
    }

    func testLayoutIsExactlyUnderPureVoiceBooksAndExtensionIsNormalized() throws {
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let bookID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let source = temporaryRoot.appendingPathComponent("Incoming.EPUB")
        try Data("book".utf8).write(to: source)

        let imported = try store.importOriginal(from: source, bookID: bookID)

        let directory = temporaryRoot
            .appendingPathComponent("PureVoice/Books", isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
        XCTAssertEqual(imported, directory.appendingPathComponent("original.epub"))
        XCTAssertEqual(store.canonicalURL(for: bookID), directory.appendingPathComponent("publication.epub"))
        XCTAssertEqual(store.coverURL(for: bookID), directory.appendingPathComponent("cover"))
        XCTAssertEqual(try Data(contentsOf: imported), Data("book".utf8))
    }

    func testImportCopiesSourceAndAtomicallyReplacesExistingDestination() throws {
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let bookID = UUID()
        let source = temporaryRoot.appendingPathComponent("source.Txt")
        try Data("first".utf8).write(to: source)
        let destination = try store.importOriginal(from: source, bookID: bookID)
        try Data("second".utf8).write(to: source)

        let replacedDestination = try store.importOriginal(from: source, bookID: bookID)

        XCTAssertEqual(destination, replacedDestination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("second".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("second".utf8))
    }

    func testTwoStoreInstancesSerializeImportsForSameBook() throws {
        let bookID = UUID()
        let firstSource = temporaryRoot.appendingPathComponent("first.txt")
        let secondSource = temporaryRoot.appendingPathComponent("second.epub")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)
        let firstReachedCommit = DispatchSemaphore(value: 0)
        let releaseFirstCommit = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondEnteredImport = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)
        let errors = LockedErrorBox()
        let firstStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .installStagedDirectory {
                    firstReachedCommit.signal()
                    guard releaseFirstCommit.wait(timeout: .now() + 5) == .success else {
                        throw InjectedFileOperationError.timeout
                    }
                }
            }
        )
        let secondStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .beginImport {
                    secondEnteredImport.signal()
                }
            }
        )

        DispatchQueue.global().async {
            do {
                _ = try firstStore.importOriginal(from: firstSource, bookID: bookID)
            } catch {
                errors.append(error)
            }
            firstFinished.signal()
        }
        XCTAssertEqual(firstReachedCommit.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            do {
                _ = try secondStore.importOriginal(from: secondSource, bookID: bookID)
            } catch {
                errors.append(error)
            }
            secondFinished.signal()
        }

        XCTAssertEqual(secondEnteredImport.wait(timeout: .now() + 0.2), .timedOut)
        releaseFirstCommit.signal()
        XCTAssertEqual(firstFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(secondEnteredImport.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(secondFinished.wait(timeout: .now() + 5), .success)

        let directory = secondStore.booksRoot.appendingPathComponent(bookID.uuidString)
        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            ["original.epub"]
        )
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("original.epub")),
            Data("second".utf8)
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: secondStore.booksRoot.path),
            [bookID.uuidString]
        )
    }

    func testTwoStoreInstancesSerializeImportAndDeleteForSameBook() throws {
        let bookID = UUID()
        let originalSource = temporaryRoot.appendingPathComponent("original.txt")
        let replacementSource = temporaryRoot.appendingPathComponent("replacement.epub")
        try Data("original".utf8).write(to: originalSource)
        try Data("replacement".utf8).write(to: replacementSource)
        let setupStore = try BookFileStore(applicationSupportRoot: temporaryRoot)
        _ = try setupStore.importOriginal(from: originalSource, bookID: bookID)
        let importReachedCommit = DispatchSemaphore(value: 0)
        let releaseImportCommit = DispatchSemaphore(value: 0)
        let importFinished = DispatchSemaphore(value: 0)
        let deleteEntered = DispatchSemaphore(value: 0)
        let deleteFinished = DispatchSemaphore(value: 0)
        let errors = LockedErrorBox()
        let importingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .installStagedDirectory {
                    importReachedCommit.signal()
                    guard releaseImportCommit.wait(timeout: .now() + 5) == .success else {
                        throw InjectedFileOperationError.timeout
                    }
                }
            }
        )
        let deletingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .beginDelete {
                    deleteEntered.signal()
                }
            }
        )

        DispatchQueue.global().async {
            do {
                _ = try importingStore.importOriginal(from: replacementSource, bookID: bookID)
            } catch {
                errors.append(error)
            }
            importFinished.signal()
        }
        XCTAssertEqual(importReachedCommit.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            do {
                try deletingStore.deleteBookFiles(bookID: bookID)
            } catch {
                errors.append(error)
            }
            deleteFinished.signal()
        }

        XCTAssertEqual(deleteEntered.wait(timeout: .now() + 0.2), .timedOut)
        releaseImportCommit.signal()
        XCTAssertEqual(importFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(deleteEntered.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(deleteFinished.wait(timeout: .now() + 5), .success)

        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: setupStore.booksRoot.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: setupStore.booksRoot.path),
            []
        )
    }

    func testInitializationRecoversInterruptedTransactionsWithoutImport() throws {
        let bookID = UUID()
        let transactionID = UUID()
        let booksRoot = temporaryRoot
            .appendingPathComponent("PureVoice", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
        let backup = booksRoot.appendingPathComponent(
            ".\(bookID.uuidString).backup-\(transactionID.uuidString)",
            isDirectory: true
        )
        let staging = booksRoot.appendingPathComponent(
            ".\(bookID.uuidString).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let malformed = booksRoot.appendingPathComponent(
            ".\(bookID.uuidString).backup-not-a-uuid",
            isDirectory: true
        )
        let unrelated = booksRoot.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: backup.appendingPathComponent("original.txt"))
        try Data("publication".utf8).write(to: backup.appendingPathComponent("publication.epub"))
        try Data("new".utf8).write(to: staging.appendingPathComponent("original.epub"))

        let recoveredStore = try BookFileStore(applicationSupportRoot: temporaryRoot)

        let directory = recoveredStore.booksRoot.appendingPathComponent(bookID.uuidString)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            ["original.txt", "publication.epub"]
        )
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("original.txt")),
            Data("old".utf8)
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: booksRoot.path).sorted(),
            [bookID.uuidString, malformed.lastPathComponent, unrelated.lastPathComponent].sorted()
        )
    }

    func testImportWithNewExtensionRemovesOnlyThePreviousOriginalAfterCopySucceeds() throws {
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let bookID = UUID()
        let textSource = temporaryRoot.appendingPathComponent("source.txt")
        let epubSource = temporaryRoot.appendingPathComponent("source.epub")
        try Data("text".utf8).write(to: textSource)
        try Data("epub".utf8).write(to: epubSource)
        let textDestination = try store.importOriginal(from: textSource, bookID: bookID)
        let directory = textDestination.deletingLastPathComponent()
        let canonical = directory.appendingPathComponent("publication.epub")
        let cover = directory.appendingPathComponent("cover")
        let temporary = directory.appendingPathComponent(".import-existing")
        try Data("canonical".utf8).write(to: canonical)
        try Data("cover".utf8).write(to: cover)
        try Data("temporary".utf8).write(to: temporary)

        let epubDestination = try store.importOriginal(from: epubSource, bookID: bookID)

        let originalFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("original.") }
        XCTAssertEqual(epubDestination.lastPathComponent, "original.epub")
        XCTAssertEqual(try Data(contentsOf: epubDestination), Data("epub".utf8))
        XCTAssertEqual(originalFiles.map(\.lastPathComponent), ["original.epub"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: textDestination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: textSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: epubSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cover.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testFailedDirectoryCommitRestoresEntirePreviousBookDirectory() throws {
        let bookID = UUID()
        let textSource = temporaryRoot.appendingPathComponent("source.txt")
        let epubSource = temporaryRoot.appendingPathComponent("source.epub")
        try Data("old original".utf8).write(to: textSource)
        try Data("new original".utf8).write(to: epubSource)
        let setupStore = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let oldOriginal = try setupStore.importOriginal(from: textSource, bookID: bookID)
        let directory = oldOriginal.deletingLastPathComponent()
        let canonical = directory.appendingPathComponent("publication.epub")
        let cover = directory.appendingPathComponent("cover")
        try Data("canonical".utf8).write(to: canonical)
        try Data("cover".utf8).write(to: cover)
        let failingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .installStagedDirectory {
                    throw InjectedFileOperationError.commit
                }
            }
        )

        XCTAssertThrowsError(try failingStore.importOriginal(from: epubSource, bookID: bookID)) { error in
            XCTAssertEqual(error as? InjectedFileOperationError, .commit)
        }

        let rootEntries = try FileManager.default.contentsOfDirectory(
            at: setupStore.booksRoot,
            includingPropertiesForKeys: nil
        )
        let bookEntries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(rootEntries.map(\.lastPathComponent), [bookID.uuidString])
        XCTAssertEqual(
            bookEntries.map(\.lastPathComponent).sorted(),
            ["cover", "original.txt", "publication.epub"]
        )
        XCTAssertEqual(try Data(contentsOf: oldOriginal), Data("old original".utf8))
        XCTAssertEqual(try Data(contentsOf: canonical), Data("canonical".utf8))
        XCTAssertEqual(try Data(contentsOf: cover), Data("cover".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("original.epub").path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: textSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: epubSource.path))
    }

    func testNextImportReclaimsBackupLeftByFailedPostCommitCleanup() throws {
        let bookID = UUID()
        let textSource = temporaryRoot.appendingPathComponent("source.txt")
        let epubSource = temporaryRoot.appendingPathComponent("source.epub")
        try Data("old".utf8).write(to: textSource)
        try Data("new".utf8).write(to: epubSource)
        let setupStore = try BookFileStore(applicationSupportRoot: temporaryRoot)
        _ = try setupStore.importOriginal(from: textSource, bookID: bookID)
        let cleanupFailingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .removeCommittedBackup {
                    throw InjectedFileOperationError.cleanup
                }
            }
        )

        let destination = try cleanupFailingStore.importOriginal(from: epubSource, bookID: bookID)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        let entriesAfterCleanupFailure = try FileManager.default.contentsOfDirectory(
            atPath: setupStore.booksRoot.path
        )
        XCTAssertTrue(entriesAfterCleanupFailure.contains(bookID.uuidString))
        XCTAssertEqual(
            entriesAfterCleanupFailure.filter {
                $0.hasPrefix(".\(bookID.uuidString).backup-")
            }.count,
            1
        )
        XCTAssertFalse(entriesAfterCleanupFailure.contains { $0.contains(".staging-") })

        _ = try setupStore.importOriginal(from: epubSource, bookID: bookID)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: setupStore.booksRoot.path),
            [bookID.uuidString]
        )
    }

    func testDeleteRemovesTransactionArtifactsWithoutResurrectingDeletedContent() throws {
        let bookID = UUID()
        let siblingID = UUID()
        let textSource = temporaryRoot.appendingPathComponent("old.txt")
        let epubSource = temporaryRoot.appendingPathComponent("replacement.epub")
        let finalSource = temporaryRoot.appendingPathComponent("final.mobi")
        let siblingSource = temporaryRoot.appendingPathComponent("sibling.txt")
        try Data("old original".utf8).write(to: textSource)
        try Data("replacement".utf8).write(to: epubSource)
        try Data("final original".utf8).write(to: finalSource)
        try Data("sibling".utf8).write(to: siblingSource)
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let oldOriginal = try store.importOriginal(from: textSource, bookID: bookID)
        let directory = oldOriginal.deletingLastPathComponent()
        try Data("old publication".utf8).write(
            to: directory.appendingPathComponent("publication.epub")
        )
        try Data("old cover".utf8).write(to: directory.appendingPathComponent("cover"))
        let siblingOriginal = try store.importOriginal(from: siblingSource, bookID: siblingID)
        let cleanupFailingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .removeCommittedBackup {
                    throw InjectedFileOperationError.cleanup
                }
            }
        )
        _ = try cleanupFailingStore.importOriginal(from: epubSource, bookID: bookID)

        try store.deleteBookFiles(bookID: bookID)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: store.booksRoot.path),
            [siblingID.uuidString]
        )
        XCTAssertEqual(try Data(contentsOf: siblingOriginal), Data("sibling".utf8))

        let finalOriginal = try store.importOriginal(from: finalSource, bookID: bookID)

        XCTAssertEqual(finalOriginal.lastPathComponent, "original.mobi")
        XCTAssertEqual(try Data(contentsOf: finalOriginal), Data("final original".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: finalOriginal.deletingLastPathComponent().path
            ),
            ["original.mobi"]
        )
        XCTAssertEqual(try Data(contentsOf: siblingOriginal), Data("sibling".utf8))
    }

    func testDeleteThrowsOnArtifactFailureAndRetryCompletesCleanup() throws {
        let bookID = UUID()
        let siblingID = UUID()
        let oldSource = temporaryRoot.appendingPathComponent("old.txt")
        let replacementSource = temporaryRoot.appendingPathComponent("replacement.epub")
        let siblingSource = temporaryRoot.appendingPathComponent("sibling.txt")
        try Data("old".utf8).write(to: oldSource)
        try Data("replacement".utf8).write(to: replacementSource)
        try Data("sibling".utf8).write(to: siblingSource)
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        _ = try store.importOriginal(from: oldSource, bookID: bookID)
        let siblingOriginal = try store.importOriginal(from: siblingSource, bookID: siblingID)
        let cleanupFailingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if operation == .removeCommittedBackup {
                    throw InjectedFileOperationError.cleanup
                }
            }
        )
        _ = try cleanupFailingStore.importOriginal(from: replacementSource, bookID: bookID)
        var injectedFailure = false
        let deleteFailingStore = try BookFileStore(
            applicationSupportRoot: temporaryRoot,
            transactionHook: { operation in
                if case let .removeBookArtifact(name) = operation,
                   name == bookID.uuidString,
                   !injectedFailure {
                    injectedFailure = true
                    throw InjectedFileOperationError.delete
                }
            }
        )

        XCTAssertThrowsError(try deleteFailingStore.deleteBookFiles(bookID: bookID)) { error in
            XCTAssertEqual(error as? InjectedFileOperationError, .delete)
        }

        try deleteFailingStore.deleteBookFiles(bookID: bookID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.booksRoot.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: store.booksRoot.path),
            [siblingID.uuidString]
        )
        XCTAssertEqual(try Data(contentsOf: siblingOriginal), Data("sibling".utf8))
    }

    func testMissingAndUnsafeExtensionsAreRejected() throws {
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let missing = temporaryRoot.appendingPathComponent("book")
        try Data().write(to: missing)

        XCTAssertThrowsError(try store.importOriginal(from: missing, bookID: UUID())) { error in
            XCTAssertEqual(error as? BookFileError, .missingExtension)
        }

        let unsafe = temporaryRoot.appendingPathComponent("book.bad%2Fext")
        try Data().write(to: unsafe)
        XCTAssertThrowsError(try store.importOriginal(from: unsafe, bookID: UUID())) { error in
            XCTAssertEqual(error as? BookFileError, .invalidExtension)
        }
    }

    func testExact250MiBBoundaryIsAllowedAndOneByteMoreIsRejected() throws {
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let boundary = temporaryRoot.appendingPathComponent("boundary.epub")
        try makeSparseFile(at: boundary, size: BookFileStore.maximumImportSize)

        let imported = try store.importOriginal(from: boundary, bookID: UUID())
        let importedSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: imported.path)[.size] as? NSNumber
        ).int64Value
        XCTAssertEqual(importedSize, BookFileStore.maximumImportSize)

        let oversized = temporaryRoot.appendingPathComponent("oversized.mobi")
        try makeSparseFile(at: oversized, size: BookFileStore.maximumImportSize + 1)
        XCTAssertThrowsError(try store.importOriginal(from: oversized, bookID: UUID())) { error in
            XCTAssertEqual(
                error as? BookFileError,
                .tooLarge(actualBytes: BookFileStore.maximumImportSize + 1, maximumBytes: BookFileStore.maximumImportSize)
            )
        }
    }

    func testDeleteRemovesOnlyRequestedBookDirectory() throws {
        let store = try BookFileStore(applicationSupportRoot: temporaryRoot)
        let firstID = UUID()
        let siblingID = UUID()
        let firstSource = temporaryRoot.appendingPathComponent("first.txt")
        let siblingSource = temporaryRoot.appendingPathComponent("sibling.epub")
        try Data("first".utf8).write(to: firstSource)
        try Data("sibling".utf8).write(to: siblingSource)
        let firstFile = try store.importOriginal(from: firstSource, bookID: firstID)
        let siblingFile = try store.importOriginal(from: siblingSource, bookID: siblingID)

        try store.deleteBookFiles(bookID: firstID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstFile.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.booksRoot.path))
    }

    func testOutOfSpaceCocoaErrorIsTranslated() {
        let cocoaError = CocoaError(.fileWriteOutOfSpace)

        XCTAssertEqual(
            BookFileStore.translateFileError(cocoaError) as? BookFileError,
            .outOfSpace
        )
    }

    func testWrappedAndDetailedOutOfSpaceErrorsAreTranslated() {
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: CocoaError(.fileWriteOutOfSpace)]
        )
        let detailed = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: ["NSDetailedErrors": [wrapped]]
        )

        XCTAssertEqual(
            BookFileStore.translateFileError(detailed) as? BookFileError,
            .outOfSpace
        )
    }

    func testPOSIXOutOfSpaceErrorIsTranslated() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))

        XCTAssertEqual(
            BookFileStore.translateFileError(error) as? BookFileError,
            .outOfSpace
        )
    }

    func testNonOutOfSpaceErrorIsReturnedUnchanged() {
        let original = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoSuchFile.rawValue
        )

        let translated = BookFileStore.translateFileError(original) as NSError

        XCTAssertTrue(translated === original)
    }

    private func makeSparseFile(at url: URL, size: Int64) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }
}

private enum InjectedFileOperationError: Error, Equatable {
    case commit
    case cleanup
    case delete
    case timeout
}

private final class LockedErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.withLock { storage }
    }

    func append(_ error: Error) {
        lock.withLock { storage.append(error) }
    }
}
