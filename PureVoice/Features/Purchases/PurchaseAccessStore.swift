import Foundation

enum ServerGrantEntitlement: String, Codable, Equatable, Sendable {
    case lifetimeFree = "lifetime-free"
}

protocol ServerGrantEntitlementProviding: Sendable {
    func entitlement(for identity: TransferIdentity) async throws -> ServerGrantEntitlement?
}

final class LocalServerGrantEntitlementProvider: ServerGrantEntitlementProviding, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entitlement(for identity: TransferIdentity) async throws -> ServerGrantEntitlement? {
        defaults.bool(forKey: Self.key(for: identity.deviceID)) ? .lifetimeFree : nil
    }

    func setLifetimeFree(_ enabled: Bool, for deviceID: UUID) {
        defaults.set(enabled, forKey: Self.key(for: deviceID))
    }

    private static func key(for deviceID: UUID) -> String {
        "purchase.serverGrant.local.\(deviceID.uuidString.lowercased())"
    }
}

struct URLSessionServerGrantEntitlementProvider: ServerGrantEntitlementProviding {
    let baseURL: URL
    let transport: any WebTransferTransport

    init(baseURL: URL, transport: any WebTransferTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func entitlement(for identity: TransferIdentity) async throws -> ServerGrantEntitlement? {
        var request = URLRequest(url: baseURL.appendingPathComponent("entitlement"))
        request.httpMethod = "GET"
        request.setValue(identity.deviceID.uuidString.lowercased(), forHTTPHeaderField: "x-transfer-device-id")
        request.setValue(identity.deviceSecret, forHTTPHeaderField: "x-transfer-device-secret")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebTransferError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw WebTransferError.invalidResponse }
        return try JSONDecoder().decode(ServerGrantEntitlementResponse.self, from: data).entitlement
    }
}

private struct ServerGrantEntitlementResponse: Decodable {
    let entitlement: ServerGrantEntitlement?
}

@MainActor
final class PurchaseAccessStore: ObservableObject {
    static let trialDuration: TimeInterval = 3 * 24 * 60 * 60
    static let installDateKey = "purchase.installDate"
    static let entitlementKey = "purchase.isEntitled"
    static let serverGrantEntitlementKey = "purchase.serverGrantEntitlement"

    @Published private(set) var installDate: Date
    @Published private(set) var storeKitEntitled: Bool
    @Published private(set) var serverGrantEntitlement: ServerGrantEntitlement?

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let storedDate = defaults.object(forKey: Self.installDateKey) as? Date {
            installDate = storedDate
        } else {
            let currentDate = now()
            installDate = currentDate
            defaults.set(currentDate, forKey: Self.installDateKey)
        }
        storeKitEntitled = defaults.bool(forKey: Self.entitlementKey)
        if let rawEntitlement = defaults.string(forKey: Self.serverGrantEntitlementKey) {
            serverGrantEntitlement = ServerGrantEntitlement(rawValue: rawEntitlement)
        } else {
            serverGrantEntitlement = nil
        }
    }

    var isEntitled: Bool {
        storeKitEntitled || serverGrantEntitlement == .lifetimeFree
    }

    var requiresPurchase: Bool {
        !isEntitled && now() >= trialExpirationDate
    }

    var remainingTrialDays: Int {
        guard !isEntitled else { return 0 }
        let remaining = trialExpirationDate.timeIntervalSince(now())
        guard remaining > 0 else { return 0 }
        return max(1, Int(ceil(remaining / (24 * 60 * 60))))
    }

    var trialExpirationDate: Date {
        installDate.addingTimeInterval(Self.trialDuration)
    }

    func updateEntitlement(isEntitled: Bool) {
        storeKitEntitled = isEntitled
        defaults.set(isEntitled, forKey: Self.entitlementKey)
    }

    func updateServerGrantEntitlement(_ entitlement: ServerGrantEntitlement?) {
        serverGrantEntitlement = entitlement
        if let entitlement {
            defaults.set(entitlement.rawValue, forKey: Self.serverGrantEntitlementKey)
        } else {
            defaults.removeObject(forKey: Self.serverGrantEntitlementKey)
        }
    }
}
