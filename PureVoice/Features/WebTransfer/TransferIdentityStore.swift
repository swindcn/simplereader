import Foundation
import Security

enum TransferIdentityStoreError: Error, Equatable {
    case unavailable
}

protocol TransferIdentityStoring: Sendable {
    func identity() throws -> TransferIdentity
    func reset() throws
}

final class InMemoryTransferIdentityStore: TransferIdentityStoring, @unchecked Sendable {
    private var stored: TransferIdentity?

    init(stored: TransferIdentity? = nil) {
        self.stored = stored
    }

    func identity() throws -> TransferIdentity {
        if let stored { return stored }
        let identity = TransferIdentity.generate()
        stored = identity
        return identity
    }

    func reset() throws {
        stored = nil
    }
}

final class KeychainTransferIdentityStore: TransferIdentityStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "com.taotaoxiaoshuo.purevoice.web-transfer",
        account: String = "transfer-identity"
    ) {
        self.service = service
        self.account = account
    }

    func identity() throws -> TransferIdentity {
        if let existing = try read() { return existing }
        let generated = TransferIdentity.generate()
        try save(generated)
        return generated
    }

    func reset() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func read() throws -> TransferIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw TransferIdentityStoreError.unavailable
        }
        do {
            return try JSONDecoder().decode(TransferIdentity.self, from: data)
        } catch {
            throw TransferIdentityStoreError.unavailable
        }
    }

    private func save(_ identity: TransferIdentity) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(identity)
        } catch {
            throw TransferIdentityStoreError.unavailable
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TransferIdentityStoreError.unavailable }
    }
}
