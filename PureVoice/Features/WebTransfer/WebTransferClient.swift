import Foundation

protocol WebTransferTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: WebTransferTransport {}

protocol WebTransferClient: Sendable {
    func register(identity: TransferIdentity) async throws
    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode
    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem]
    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL
    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws
    func delete(uploadID: UUID, identity: TransferIdentity) async throws
    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL
}

struct URLSessionWebTransferClient: WebTransferClient {
    let baseURL: URL
    let transport: any WebTransferTransport
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init(baseURL: URL, transport: any WebTransferTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func register(identity: TransferIdentity) async throws {
        let body = [
            "deviceId": identity.deviceID.uuidString.lowercased(),
            "deviceSecret": identity.deviceSecret
        ]
        _ = try await send(
            path: "device/register",
            method: "POST",
            identity: nil,
            body: body,
            response: TransferRegisterResponse.self
        )
    }

    func createPairingCode(identity: TransferIdentity) async throws -> TransferPairingCode {
        try await send(
            path: "pairing-code",
            method: "POST",
            identity: identity,
            body: EmptyBody?.none,
            response: TransferPairingCode.self
        )
    }

    func inbox(identity: TransferIdentity) async throws -> [TransferInboxItem] {
        let response = try await send(
            path: "inbox",
            method: "GET",
            identity: identity,
            body: EmptyBody?.none,
            response: TransferInboxResponse.self
        )
        return response.items
    }

    func downloadURL(uploadID: UUID, identity: TransferIdentity) async throws -> URL {
        let response = try await send(
            path: "uploads/\(uploadID.uuidString.lowercased())/download-url",
            method: "POST",
            identity: identity,
            body: EmptyBody?.none,
            response: TransferDownloadURLResponse.self
        )
        return response.downloadUrl
    }

    func claim(uploadID: UUID, identity: TransferIdentity, importedBookID: UUID?) async throws {
        let body = ["importedBookId": importedBookID?.uuidString.lowercased() ?? ""]
        _ = try await send(
            path: "uploads/\(uploadID.uuidString.lowercased())/claim",
            method: "POST",
            identity: identity,
            body: body,
            response: TransferStatusResponse.self
        )
    }

    func delete(uploadID: UUID, identity: TransferIdentity) async throws {
        _ = try await send(
            path: "uploads/\(uploadID.uuidString.lowercased())",
            method: "DELETE",
            identity: identity,
            body: EmptyBody?.none,
            response: TransferStatusResponse.self
        )
    }

    func downloadFile(from url: URL, suggestedFilename: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await transport.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WebTransferError.downloadFailed }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-transfer-\(UUID().uuidString)-\(suggestedFilename)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        identity: TransferIdentity?,
        body: Body?,
        response: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let identity {
            request.setValue(identity.deviceID.uuidString.lowercased(), forHTTPHeaderField: "x-transfer-device-id")
            request.setValue(identity.deviceSecret, forHTTPHeaderField: "x-transfer-device-secret")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        let (data, urlResponse) = try await transport.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw WebTransferError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            if let decoded = try? decoder.decode(TransferErrorResponse.self, from: data) {
                throw WebTransferError.server(decoded.error.message)
            }
            throw WebTransferError.invalidResponse
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct EmptyBody: Encodable {}
