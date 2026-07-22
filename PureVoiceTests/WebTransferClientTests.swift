import XCTest
@testable import PureVoice

final class WebTransferClientTests: XCTestCase {
    func testRequestUsesDeviceHeaders() async throws {
        let transport = RecordingWebTransferTransport(data: #"{"items":[]}"#.data(using: .utf8)!)
        let client = URLSessionWebTransferClient(
            baseURL: URL(string: "https://example.com/functions/v1/transfer")!,
            transport: transport
        )
        let identity = TransferIdentity(
            deviceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            deviceSecret: "secret-secret-secret-secret-secret"
        )

        _ = try await client.inbox(identity: identity)

        let recordedRequest = await transport.recordedRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-transfer-device-id"), identity.deviceID.uuidString.lowercased())
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-transfer-device-secret"), identity.deviceSecret)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/functions/v1/transfer/inbox")
    }

    func testServerErrorUsesReturnedMessage() async throws {
        let data = #"{"error":{"code":"expired","message":"文件已过期"}}"#.data(using: .utf8)!
        let transport = RecordingWebTransferTransport(data: data, statusCode: 410)
        let client = URLSessionWebTransferClient(
            baseURL: URL(string: "https://example.com/functions/v1/transfer")!,
            transport: transport
        )
        let identity = TransferIdentity(
            deviceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            deviceSecret: "secret-secret-secret-secret-secret"
        )

        do {
            _ = try await client.inbox(identity: identity)
            XCTFail("Expected server error")
        } catch let error as WebTransferError {
            XCTAssertEqual(error, .server("文件已过期"))
        }
    }
}

private actor RecordingWebTransferTransport: WebTransferTransport {
    private var lastRequest: URLRequest?
    let data: Data
    let statusCode: Int

    init(data: Data, statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func recordedRequest() -> URLRequest? {
        lastRequest
    }
}
