import Foundation

/// 広告除去などの購入(§8.3)。P1 は StoreKit を入れていないので、購入できない実装だけを置く。
/// P3 で StoreKit 2 の実装(Product.products(for:)・Transaction.currentEntitlements)に差し替える。
protocol StoreService {
    /// 扱う商品 ID(将来枠もここに足す)。
    var productIds: [String] { get }
    /// 購入できる状態か。
    var isAvailable: Bool { get }
    /// 表示する価格(ストアから取る。ハードコードしない)。取れなければ nil。
    func displayPrice(for productId: String) async -> String?
    /// 購入する。成功したら true。
    func purchase(_ productId: String) async -> Bool
    /// 購入を復元する。広告除去が有効なら true。
    func restore() async -> Bool
    /// いまの権利(広告除去済みか)。
    func adsRemovedEntitlement() async -> Bool
}

enum ProductID {
    static let removeAds = "reforge.remove_ads"
}

/// P1 用: 何も買えない。
struct UnavailableStoreService: StoreService {
    let productIds = [ProductID.removeAds]
    let isAvailable = false

    func displayPrice(for productId: String) async -> String? { nil }
    func purchase(_ productId: String) async -> Bool { false }
    func restore() async -> Bool { false }
    func adsRemovedEntitlement() async -> Bool { false }
}
