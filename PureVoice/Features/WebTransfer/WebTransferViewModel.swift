import Foundation

protocol TransferImporting: Sendable {
    func importBook(from sourceURL: URL) async throws -> UUID?
}

enum WebTransferImportError: Error {
    case importDidNotComplete
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
    @Published private(set) var deviceTransferID = "不可用"
    @Published var error: UserFacingError?
    let webTransferPageURL: URL

    private let identityStore: any TransferIdentityStoring
    private let client: any WebTransferClient
    private let importCoordinator: (any TransferImporting)?
    private let pairingCodeDefaults: UserDefaults
    private let pairingCodeKeyPrefix = "purevoice.webTransfer.pairingCode."

    init(
        identityStore: any TransferIdentityStoring,
        client: any WebTransferClient,
        importCoordinator: (any TransferImporting)?,
        webTransferPageURL: URL = URL(string: "https://swindcn.github.io/simplereader/")!,
        pairingCodeDefaults: UserDefaults = .standard
    ) {
        self.identityStore = identityStore
        self.client = client
        self.importCoordinator = importCoordinator
        self.webTransferPageURL = webTransferPageURL
        self.pairingCodeDefaults = pairingCodeDefaults
        self.deviceTransferID = (try? identityStore.identity().deviceID.uuidString.uppercased()) ?? "不可用"
    }

    func generateCode() async {
        await run { [self] in
            let identity = try self.identityStore.identity()
            try await self.client.register(identity: identity)
            let generatedCode = try await self.client.createPairingCode(identity: identity)
            self.savePairingCode(generatedCode, for: identity.deviceID)
            self.pairingCode = generatedCode
        }
    }

    func prepareTransferCode() async {
        guard pairingCode == nil else { return }
        do {
            let identity = try identityStore.identity()
            if let cachedCode = cachedPairingCode(for: identity.deviceID) {
                pairingCode = cachedCode
                try? await client.register(identity: identity)
                return
            }
        } catch let identityError as TransferIdentityStoreError {
            error = UserFacingError(transferIdentityError: identityError)
            return
        } catch {
            self.error = UserFacingError(
                title: "传书码不可用",
                message: "无法读取本机传书码。",
                recoveryAction: "稍后重试"
            )
            return
        }
        await generateCode()
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
            guard let importedBookID = try await importCoordinator.importBook(from: localURL) else {
                throw WebTransferImportError.importDidNotComplete
            }
            try await self.client.claim(uploadID: item.id, identity: identity, importedBookID: importedBookID)
            self.inbox.removeAll { $0.id == item.id }
        }
    }

    @discardableResult
    func receivePendingItems() async -> Int {
        guard let importCoordinator else {
            error = UserFacingError(
                title: "导入功能不可用",
                message: "当前无法导入网站传书文件。",
                recoveryAction: "稍后重试"
            )
            return 0
        }

        var importedCount = 0
        await run { [self] in
            let identity = try self.identityStore.identity()
            let items = try await self.client.inbox(identity: identity)
            self.inbox = items
            for item in items {
                let url = try await self.client.downloadURL(uploadID: item.id, identity: identity)
                let localURL = try await self.client.downloadFile(from: url, suggestedFilename: item.filename)
                guard let importedBookID = try await importCoordinator.importBook(from: localURL) else {
                    throw WebTransferImportError.importDidNotComplete
                }
                try await self.client.claim(uploadID: item.id, identity: identity, importedBookID: importedBookID)
                self.inbox.removeAll { $0.id == item.id }
                importedCount += 1
            }
        }
        return importedCount
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

    private func cachedPairingCode(for deviceID: UUID) -> TransferPairingCode? {
        let key = pairingCodeKey(for: deviceID)
        guard let code = pairingCodeDefaults.string(forKey: key),
              code.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil
        else { return nil }
        return TransferPairingCode(code: code, expiresAt: nil)
    }

    private func savePairingCode(_ pairingCode: TransferPairingCode, for deviceID: UUID) {
        pairingCodeDefaults.set(pairingCode.code, forKey: pairingCodeKey(for: deviceID))
    }

    private func pairingCodeKey(for deviceID: UUID) -> String {
        pairingCodeKeyPrefix + deviceID.uuidString.lowercased()
    }
}
