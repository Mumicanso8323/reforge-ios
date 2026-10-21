import Foundation
import StoreKit

/// StoreKit 2 purchase boundary.  Rights are always derived from signed local transactions.
protocol StoreService {
    /// 扱う商品 ID(将来枠もここに足す)。
    var productIds: [String] { get }
    /// 購入できる状態か。
    var isAvailable: Bool { get }
    /// 表示する価格(ストアから取る。ハードコードしない)。取れなければ nil。
    func displayPrice(for productId: String) async -> String?
    /// 購入する。成功したら true。
    func purchase(_ productId: String) async -> Bool
    /// 購入を復元する。
    func restore() async -> Bool
    /// いまの権利。
    func entitlements() async -> Set<String>
}

enum ProductID {
    static let fullGame = "reforge.fullgame"
}

/// P1 用: 何も買えない。
struct UnavailableStoreService: StoreService {
    let productIds = [ProductID.fullGame]
    let isAvailable = false

    func displayPrice(for productId: String) async -> String? { nil }
    func purchase(_ productId: String) async -> Bool { false }
    func restore() async -> Bool { false }
    func entitlements() async -> Set<String> { [] }
}

/// StoreKit supplies locally-verifiable entitlement records even while offline.
struct StoreKitStoreService: StoreService {
    let productIds = [ProductID.fullGame]
    let isAvailable = true

    func displayPrice(for productId: String) async -> String? {
        (try? await Product.products(for: [productId]))?.first?.displayPrice
    }

    func purchase(_ productId: String) async -> Bool {
        guard let products = try? await Product.products(for: [productId]), let product = products.first else { return false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let transaction) = result { await transaction.finish(); return true }
            case .pending, .userCancelled: break
            @unknown default: break
            }
        } catch { }
        return false
    }

    func restore() async -> Bool {
        do { try await AppStore.sync() } catch { return false }
        return !(await entitlements()).isEmpty
    }

    func entitlements() async -> Set<String> {
        var result = Set<String>()
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification, transaction.revocationDate == nil else { continue }
            result.insert(transaction.productID)
        }
        return result
    }
}
