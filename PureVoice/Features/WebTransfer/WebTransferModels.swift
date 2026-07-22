import Foundation

enum WebTransferError: Error, Equatable, Sendable {
    case server(String)
    case invalidResponse
    case downloadFailed
}

struct TransferPairingCode: Equatable, Decodable, Sendable {
    let code: String
    let expiresAt: Date?
}

struct TransferInboxItem: Identifiable, Equatable, Decodable, Sendable {
    let id: UUID
    let filename: String
    let byteSize: Int64
    let format: String
    let createdAt: Date
    let expiresAt: Date
}

struct TransferInboxResponse: Decodable, Sendable {
    let items: [TransferInboxItem]
}

struct TransferDownloadURLResponse: Decodable, Sendable {
    let downloadUrl: URL
    let expiresInSeconds: Int
}

struct TransferRegisterResponse: Decodable, Sendable {
    let deviceId: UUID
    let registered: Bool
}

struct TransferStatusResponse: Decodable, Sendable {
    let status: String
}

struct TransferErrorResponse: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }

    let error: Payload
}
