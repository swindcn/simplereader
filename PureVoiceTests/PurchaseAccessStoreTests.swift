import XCTest
@testable import PureVoice

@MainActor
final class PurchaseAccessStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var now: Date!

    override func setUp() {
        super.setUp()
        suiteName = "PurchaseAccessStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        now = Date(timeIntervalSince1970: 1_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        now = nil
        super.tearDown()
    }

    func testNewInstallReceivesThreeDayTrialAccess() {
        let store = makeStore()

        XCTAssertFalse(store.requiresPurchase)
        XCTAssertEqual(store.remainingTrialDays, 3)
    }

    func testTrialExpiresAfterThreeDaysWithoutPurchase() {
        _ = makeStore()
        now = now.addingTimeInterval((3 * 24 * 60 * 60) + 1)
        let restored = makeStore()

        XCTAssertTrue(restored.requiresPurchase)
        XCTAssertEqual(restored.remainingTrialDays, 0)
    }

    func testPaidEntitlementKeepsAccessAfterTrialExpires() {
        let store = makeStore()
        store.updateEntitlement(isEntitled: true)
        now = now.addingTimeInterval(30 * 24 * 60 * 60)
        let restored = makeStore()

        XCTAssertFalse(restored.requiresPurchase)
        XCTAssertTrue(restored.isEntitled)
    }

    func testServerGrantKeepsAccessAfterTrialExpires() {
        let store = makeStore()
        store.updateServerGrantEntitlement(.lifetimeFree)
        now = now.addingTimeInterval(30 * 24 * 60 * 60)
        let restored = makeStore()

        XCTAssertFalse(restored.requiresPurchase)
        XCTAssertTrue(restored.isEntitled)
    }

    func testStoreKitRefreshDoesNotClearServerGrantAccess() {
        let store = makeStore()
        store.updateServerGrantEntitlement(.lifetimeFree)
        store.updateEntitlement(isEntitled: false)
        now = now.addingTimeInterval(30 * 24 * 60 * 60)

        XCTAssertFalse(store.requiresPurchase)
        XCTAssertTrue(store.isEntitled)
    }

    func testLocalServerGrantProviderCanToggleLifetimeAccess() async throws {
        let provider = LocalServerGrantEntitlementProvider(defaults: defaults)
        let identity = TransferIdentity(
            deviceID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            deviceSecret: "secret-secret-secret-secret-secret"
        )

        let missing = try await provider.entitlement(for: identity)
        XCTAssertNil(missing)

        provider.setLifetimeFree(true, for: identity.deviceID)

        let granted = try await provider.entitlement(for: identity)
        XCTAssertEqual(granted, .lifetimeFree)
    }

    func testFallbackPricesMatchReviewScreenshotPricing() {
        XCTAssertEqual(PurchaseProductKind.monthly.fallbackPrice, "$2.99")
        XCTAssertEqual(PurchaseProductKind.annual.fallbackPrice, "$14.99")
        XCTAssertEqual(PurchaseProductKind.lifetime.fallbackPrice, "$39.99")
    }

    private func makeStore() -> PurchaseAccessStore {
        PurchaseAccessStore(defaults: defaults, now: { self.now })
    }
}
