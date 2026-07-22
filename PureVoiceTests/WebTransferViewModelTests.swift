import XCTest
@testable import PureVoice

@MainActor
final class WebTransferViewModelTests: XCTestCase {
    func testGenerateCodeRegistersDeviceAndPublishesCode() async throws {
        let client = RecordingWebTransferClient()
        let viewModel = WebTransferViewModel(
            identityStore: InMemoryTransferIdentityStore(),
            client: client,
            importCoordinator: nil
        )

        await viewModel.generateCode()

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
}

private actor RecordingTransferImporter: TransferImporting {
    private var importCount = 0
    let throwsOnImport: Bool

    init(throwsOnImport: Bool = false) {
        self.throwsOnImport = throwsOnImport
    }

    func importBook(from sourceURL: URL) async throws -> UUID? {
        importCount += 1
        if throwsOnImport { throw TestTransferError.importFailed }
        return UUID()
    }

    func count() -> Int {
        importCount
    }
}

private actor RecordingWebTransferClient: WebTransferClient {
    private var registerCount = 0
    private var createCodeCount = 0
    private var claimCount = 0

    func register(identity: TransferIdentity) async throws {
        registerCount += 1
    }

    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode {
        createCodeCount += 1
        return TransferPairingCode(code: "12345678", expiresAt: Date().addingTimeInterval(600))
    }

    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem] {
        []
    }

    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL {
        URL(string: "https://example.com/book.txt")!
    }

    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws {
        claimCount += 1
    }

    func delete(uploadID: UUID, identity: TransferIdentity) async throws {}

    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
    }

    func counts() -> (register: Int, createCode: Int, claim: Int) {
        (registerCount, createCodeCount, claimCount)
    }
}

private enum TestTransferError: Error {
    case importFailed
}
