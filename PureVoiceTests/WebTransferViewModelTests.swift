import XCTest
@testable import PureVoice

@MainActor
final class WebTransferViewModelTests: XCTestCase {
    func testGenerateCodeRegistersDeviceAndPublishesCode() async throws {
        let client = RecordingWebTransferClient()
        let identity = TransferIdentity(deviceID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, deviceSecret: "secret")
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(stored: identity),
            client: client,
            importCoordinator: nil,
            webTransferPageURL: URL(string: "https://swindcn.github.io/simplereader/")!
        )

        await viewModel.generateCode()

        XCTAssertEqual(viewModel.pairingCode?.code, "12345678")
        XCTAssertEqual(viewModel.deviceTransferID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(viewModel.webTransferPageURL.absoluteString, "https://swindcn.github.io/simplereader/")
        let counts = await client.counts()
        XCTAssertEqual(counts.register, 1)
        XCTAssertEqual(counts.createCode, 1)
    }

    func testPrepareTransferCodeGeneratesCodeOnlyOnce() async throws {
        let client = RecordingWebTransferClient()
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: nil
        )

        await viewModel.prepareTransferCode()
        await viewModel.prepareTransferCode()

        XCTAssertEqual(viewModel.pairingCode?.code, "12345678")
        let counts = await client.counts()
        XCTAssertEqual(counts.register, 1)
        XCTAssertEqual(counts.createCode, 1)
    }

    func testImportSuccessClaimsUpload() async throws {
        let client = RecordingWebTransferClient()
        let importer = RecordingTransferImporter()
        let item = TransferInboxItem(
            id: UUID(),
            filename: "book.txt",
            byteSize: 12,
            format: "txt",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: importer
        )

        await viewModel.importItem(item)

        let importCount = await importer.count()
        let clientCounts = await client.counts()
        XCTAssertEqual(importCount, 1)
        XCTAssertEqual(clientCounts.claim, 1)
    }

    func testImportFailureDoesNotClaimUpload() async throws {
        let client = RecordingWebTransferClient()
        let importer = RecordingTransferImporter(throwsOnImport: true)
        let item = TransferInboxItem(
            id: UUID(),
            filename: "book.txt",
            byteSize: 12,
            format: "txt",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: importer
        )

        await viewModel.importItem(item)

        let importCount = await importer.count()
        let clientCounts = await client.counts()
        XCTAssertEqual(importCount, 1)
        XCTAssertEqual(clientCounts.claim, 0)
        XCTAssertNotNil(viewModel.error)
    }

    func testImportWithoutCompletedBookDoesNotClaimUpload() async throws {
        let client = RecordingWebTransferClient()
        let importer = RecordingTransferImporter(completedBookID: nil)
        let item = TransferInboxItem(
            id: UUID(),
            filename: "book.epub",
            byteSize: 12,
            format: "epub",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: importer
        )

        await viewModel.importItem(item)

        let clientCounts = await client.counts()
        XCTAssertEqual(clientCounts.claim, 0)
        XCTAssertNotNil(viewModel.error)
    }

    func testReceivePendingItemsImportsAndClaimsInboxItems() async throws {
        let item = TransferInboxItem(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            filename: "将夜（精校版）.epub",
            byteSize: 6_672_303,
            format: "epub",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        let client = RecordingWebTransferClient(inboxItems: [item])
        let importer = RecordingTransferImporter()
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: importer
        )

        let importedCount = await viewModel.receivePendingItems()

        let importCount = await importer.count()
        let clientCounts = await client.counts()
        XCTAssertEqual(importedCount, 1)
        XCTAssertEqual(importCount, 1)
        XCTAssertEqual(clientCounts.inbox, 1)
        XCTAssertEqual(clientCounts.downloadURL, 1)
        XCTAssertEqual(clientCounts.downloadFile, 1)
        XCTAssertEqual(clientCounts.claim, 1)
        XCTAssertTrue(viewModel.inbox.isEmpty)
        XCTAssertNil(viewModel.error)
    }
}

private actor RecordingTransferImporter: TransferImporting {
    private var importCount = 0
    let throwsOnImport: Bool
    let completedBookID: UUID?

    init(throwsOnImport: Bool = false, completedBookID: UUID? = UUID()) {
        self.throwsOnImport = throwsOnImport
        self.completedBookID = completedBookID
    }

    func importBook(from sourceURL: URL) async throws -> UUID? {
        importCount += 1
        if throwsOnImport { throw TestTransferError.importFailed }
        return completedBookID
    }

    func count() -> Int {
        importCount
    }
}

private actor RecordingWebTransferClient: WebTransferClient {
    private var registerCount = 0
    private var createCodeCount = 0
    private var inboxCount = 0
    private var downloadURLCount = 0
    private var downloadFileCount = 0
    private var claimCount = 0
    private let inboxItems: [TransferInboxItem]

    init(inboxItems: [TransferInboxItem] = []) {
        self.inboxItems = inboxItems
    }

    func register(identity: TransferIdentity) async throws {
        registerCount += 1
    }

    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode {
        createCodeCount += 1
        return TransferPairingCode(code: "12345678", expiresAt: Date().addingTimeInterval(600))
    }

    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem] {
        inboxCount += 1
        return inboxItems
    }

    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL {
        downloadURLCount += 1
        return URL(string: "https://example.com/book.txt")!
    }

    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws {
        claimCount += 1
    }

    func delete(uploadID: UUID, identity: TransferIdentity) async throws {}

    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL {
        downloadFileCount += 1
        return FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
    }

    func counts() -> (register: Int, createCode: Int, inbox: Int, downloadURL: Int, downloadFile: Int, claim: Int) {
        (registerCount, createCodeCount, inboxCount, downloadURLCount, downloadFileCount, claimCount)
    }
}

private enum TestTransferError: Error {
    case importFailed
}
