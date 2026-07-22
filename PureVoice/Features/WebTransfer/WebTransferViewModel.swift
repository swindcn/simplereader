import Foundation

protocol TransferImporting: Sendable {
    func importBook(from sourceURL: URL) async throws -> UUID?
}

struct ImportCoordinatorTransferImporter: TransferImporting {
    let coordinator: ImportCoordinator

    @MainActor
    func importBook(from sourceURL: URL) async throws -> UUID? {
        try await coordinator.importBook(from: sourceURL)
        if case let .completed(bookID) = coordinator.state {
            return bookID
        }
        return nil
    }
}

@MainActor
final class WebTransferViewModel: ObservableObject {
    @Published private(set) var pairingCode: TransferPairingCode?
    @Published private(set) var inbox: [TransferInboxItem] = []
    @Published private(set) var isBusy = false
    @Published var error: UserFacingError?

    private let identityStore: any TransferIdentityStoring
    private let client: any WebTransferClient
    private let importCoordinator: (any TransferImporting)?

    init(
        identityStore: any TransferIdentityStoring,
        client: any WebTransferClient,
        importCoordinator: (any TransferImporting)?
    ) {
        self.identityStore = identityStore
        self.client = client
        self.importCoordinator = importCoordinator
    }

    func generateCode() async {
        await run { [self] in
            let identity = try self.identityStore.identity()
            try await self.client.register(identity: identity)
            self.pairingCode = try await self.client.createPairingCode(identity: identity)
        }
    }

    func refreshInbox() async {
        await run { [self] in
            let identity = try self.identityStore.identity()
            self.inbox = try await self.client.inbox(identity: identity)
        }
    }

    func importItem(_ item: TransferInboxItem) async {
        guard let importCoordinator else {
            error = UserFacingError(
                title: "导入功能不可用",
                message: "当前无法导入网站传书文件。",
                recoveryAction: "稍后重试"
            )
            return
        }
        await run { [self] in
            let identity = try self.identityStore.identity()
            let url = try await self.client.downloadURL(uploadID: item.id, identity: identity)
            let localURL = try await self.client.downloadFile(from: url, suggestedFilename: item.filename)
            let importedBookID = try await importCoordinator.importBook(from: localURL)
            try await self.client.claim(uploadID: item.id, identity: identity, importedBookID: importedBookID)
            self.inbox.removeAll { $0.id == item.id }
        }
    }

    func deleteItem(_ item: TransferInboxItem) async {
        await run { [self] in
            let identity = try self.identityStore.identity()
            try await self.client.delete(uploadID: item.id, identity: identity)
            self.inbox.removeAll { $0.id == item.id }
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch let identityError as TransferIdentityStoreError {
            error = UserFacingError(transferIdentityError: identityError)
        } catch let transferError as WebTransferError {
            error = UserFacingError(webTransferError: transferError)
        } catch {
            self.error = UserFacingError(
                title: "网站传书失败",
                message: "操作没有完成。",
                recoveryAction: "稍后重试"
            )
        }
    }
}
