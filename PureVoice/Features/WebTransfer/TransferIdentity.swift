import Foundation
import Security

struct TransferIdentity: Equatable, Codable, Sendable {
    let deviceID: UUID
    let deviceSecret: String

    static func generate() -> TransferIdentity {
        TransferIdentity(deviceID: UUID(), deviceSecret: randomSecret())
    }

    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        return UUID().uuidString + UUID().uuidString
    }
}
