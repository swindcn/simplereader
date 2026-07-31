import Foundation
import StoreKit

enum PurchaseProductKind: String, CaseIterable, Identifiable {
    case monthly = "com.simplevoice.reader.pro.monthly"
    case annual = "com.simplevoice.reader.pro.annual"
    case lifetime = "com.simplevoice.reader.pro.lifetime"

    var id: String { rawValue }

    var fallbackPrice: String {
        switch self {
        case .monthly: "$2.99"
        case .annual: "$14.99"
        case .lifetime: "$39.99"
        }
    }

    func title(in strings: AppStrings) -> String {
        switch self {
        case .monthly: strings.monthlyPro
        case .annual: strings.annualPro
        case .lifetime: strings.lifetimeAccess
        }
    }

    func detail(in strings: AppStrings) -> String {
        switch self {
        case .monthly: strings.monthlyProDetail
        case .annual: strings.annualProDetail
        case .lifetime: strings.lifetimeAccessDetail
        }
    }

    func priceSuffix(in strings: AppStrings) -> String {
        switch self {
        case .monthly: strings.perMonth
        case .annual: strings.perYear
        case .lifetime: ""
        }
    }

    func subscriptionTitle(in strings: AppStrings) -> String {
        switch self {
        case .monthly: strings.monthlySubscription
        case .annual: strings.annualSubscription
        case .lifetime: strings.lifetimeSubscription
        }
    }
}

struct PurchaseProductOption: Identifiable {
    let kind: PurchaseProductKind
    let product: Product?

    var id: String { kind.id }
    var displayPrice: String { product?.displayPrice ?? kind.fallbackPrice }
}

struct PurchaseSubscriptionStatus: Equatable {
    var kind: PurchaseProductKind?
    var expirationDate: Date?

    static let notSubscribed = PurchaseSubscriptionStatus(kind: nil, expirationDate: nil)

    var isSubscribed: Bool { kind != nil }

    func displayText(in strings: AppStrings) -> String {
        guard let kind else { return strings.notSubscribed }
        if let expirationDate {
            return "\(kind.subscriptionTitle(in: strings)) · \(strings.subscriptionExpires(expirationDate))"
        }
        return kind.subscriptionTitle(in: strings)
    }

    func accessibilityText(in strings: AppStrings) -> String {
        guard isSubscribed else { return strings.notSubscribed }
        return "\(strings.activeSubscription)，\(displayText(in: strings))"
    }
}

@MainActor
final class StoreKitPurchaseManager: ObservableObject {
    @Published private(set) var options: [PurchaseProductOption] = PurchaseProductKind.allCases.map {
        PurchaseProductOption(kind: $0, product: nil)
    }
    @Published private(set) var isLoading = false
    @Published private(set) var subscriptionStatus: PurchaseSubscriptionStatus = .notSubscribed
    @Published var errorMessage: String?

    private let accessStore: PurchaseAccessStore

    init(accessStore: PurchaseAccessStore) {
        self.accessStore = accessStore
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: PurchaseProductKind.allCases.map(\.id))
            options = PurchaseProductKind.allCases.map { kind in
                PurchaseProductOption(
                    kind: kind,
                    product: products.first { $0.id == kind.id }
                )
            }
        } catch {
            errorMessage = "无法载入购买项目，请稍后重试。"
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        var activeStatus: PurchaseSubscriptionStatus?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  let kind = PurchaseProductKind(rawValue: transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            activeStatus = PurchaseSubscriptionStatus(kind: kind, expirationDate: transaction.expirationDate)
            accessStore.updateEntitlement(isEntitled: true)
            subscriptionStatus = activeStatus ?? .notSubscribed
            return true
        }
        accessStore.updateEntitlement(isEntitled: false)
        subscriptionStatus = .notSubscribed
        return false
    }

    @discardableResult
    func purchase(_ option: PurchaseProductOption) async -> Bool {
        guard let product = option.product else {
            errorMessage = "购买项目还没有准备好，请稍后重试。"
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try verifiedTransaction(from: verification)
                await transaction.finish()
                accessStore.updateEntitlement(isEntitled: true)
                if let kind = PurchaseProductKind(rawValue: transaction.productID) {
                    subscriptionStatus = PurchaseSubscriptionStatus(kind: kind, expirationDate: transaction.expirationDate)
                }
                return true
            case .pending:
                errorMessage = "购买正在处理中，请稍后回到 App 查看。"
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "购买未完成，请稍后重试。"
            }
        } catch {
            errorMessage = "购买失败，请稍后重试。"
        }
        return false
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            return await refreshEntitlements()
        } catch {
            errorMessage = "恢复购买失败，请确认网络后重试。"
            return false
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case let .verified(transaction):
            return transaction
        case .unverified:
            throw StoreKitPurchaseError.unverifiedTransaction
        }
    }
}

enum StoreKitPurchaseError: Error {
    case unverifiedTransaction
}
