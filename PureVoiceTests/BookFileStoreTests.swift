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
        let store = BookFileStore(applicationSupportRoot: temporaryRoot)
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
        let store = BookFileStore(applicationSupportRoot: temporaryRoot)
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

    func testImportWithNewExtensionRemovesOnlyThePreviousOriginalAfterCopySucceeds() throws {
        let store = BookFileStore(applicationSupportRoot: temporaryRoot)
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
        let setupStore = BookFileStore(applicationSupportRoot: temporaryRoot)
        let oldOriginal = try setupStore.importOriginal(from: textSource, bookID: bookID)
        let directory = oldOriginal.deletingLastPathComponent()
        let canonical = directory.appendingPathComponent("publication.epub")
        let cover = directory.appendingPathComponent("cover")
        try Data("canonical".utf8).write(to: canonical)
        try Data("cover".utf8).write(to: cover)
        let failingStore = BookFileStore(
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
        let setupStore = BookFileStore(applicationSupportRoot: temporaryRoot)
        _ = try setupStore.importOriginal(from: textSource, bookID: bookID)
        let cleanupFailingStore = BookFileStore(
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

    func testMissingAndUnsafeExtensionsAreRejected() throws {
        let store = BookFileStore(applicationSupportRoot: temporaryRoot)
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
        let store = BookFileStore(applicationSupportRoot: temporaryRoot)
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
        let store = BookFileStore(applicationSupportRoot: temporaryRoot)
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
}
