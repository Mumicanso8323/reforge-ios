import StoreKit
import StoreKitTest
import XCTest
@testable import ReForge

/// StoreKitTest is available in the macOS-hosted iOS test job. It owns one
/// shared test store, so this class clears it before and after each test.
@MainActor
final class StoreServiceTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "ReForge")
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() {
        session.clearTransactions()
        session = nil
        super.tearDown()
    }

    func testStoreKitPurchaseRefundRestoreAndFamilyShareableFullGame() async throws {
        let service = StoreKitStoreService()
        XCTAssertEqual(service.productIds, [ProductID.fullGame])
        // CI の記録は外れた行の番号だけを残すので、外れ方ごとに行を分ける
        let loaded = try await Product.products(for: [ProductID.fullGame])
        XCTAssertEqual(loaded.count, 1, "試験の店から商品を読めない")
        let before = await service.entitlements()
        XCTAssertFalse(before.contains(ProductID.fullGame))

        let bought = await service.purchase(ProductID.fullGame)
        if !bought, let product = loaded.first {
            do {
                switch try await product.purchase() {
                case .success(.verified(let transaction)):
                    await transaction.finish()
                    XCTFail("2 度目の購入だけが通った")
                case .success(.unverified):
                    XCTFail("取引を検証できない")
                case .pending:
                    XCTFail("購入が保留になった")
                case .userCancelled:
                    XCTFail("購入が取り消された")
                @unknown default:
                    XCTFail("購入の結果が分からない")
                }
            } catch {
                XCTFail("購入で投げた: \(error)")
            }
        }
        XCTAssertTrue(bought, "購入した検証済み取引を権利にする")
        let afterPurchase = await service.entitlements()
        XCTAssertTrue(afterPurchase.contains(ProductID.fullGame))

        let purchase = try XCTUnwrap(session.allTransactions().last { $0.productIdentifier == ProductID.fullGame })
        try session.refundTransaction(identifier: purchase.identifier)
        let afterRefund = await service.entitlements()
        XCTAssertFalse(afterRefund.contains(ProductID.fullGame), "取り消された取引は権利にしない")

        // アプリの外で買った取引を AppStore.sync() で読み直すのが復元の経路。
        try session.buyProduct(productIdentifier: ProductID.fullGame)
        let restored = await service.restore()
        XCTAssertTrue(restored)
        let afterRestore = await service.entitlements()
        XCTAssertTrue(afterRestore.contains(ProductID.fullGame))

        let products = try await Product.products(for: [ProductID.fullGame])
        XCTAssertTrue(try XCTUnwrap(products.first).isFamilyShareable)
        // StoreKitTest は別の Sandbox テスト家族の familyShared 取引を生成しない。
        // entitlements() は ownershipType を除外せず、検証済み・未取消の取引を同じ集合に入れる。
        let familyCompatible = await service.entitlements()
        XCTAssertTrue(familyCompatible.contains(ProductID.fullGame))
    }

    func testDefaultBuildKeepsTrialGateClosed() {
        let value = Bundle.main.object(forInfoDictionaryKey: "ReForgeTrialGateOpen")
        let enabled = (value as? Bool) ?? (value as? String).map { ($0 as NSString).boolValue } ?? false
        XCTAssertFalse(enabled)
    }
}
