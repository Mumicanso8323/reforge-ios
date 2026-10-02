import SwiftUI

/// S11 広告除去。設定の札の中身を差し替えて出す(札を重ねない)。
/// 価格はストアから取る(ハードコードしない)。P1 は購入できない。
struct RemoveAdsView: View {
    @Bindable var app: AppModel
    /// 設定の中身に戻る。
    var back: () -> Void
    @State private var price: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                back()
            } label: {
                Text("‹ 設定にもどる")
            }
            .buttonStyle(.ink(.quiet, fill: false))

            Text("広告を消す")
                .font(InkFont.heading)
                .tracking(InkFont.headingTracking)
            Text("広告を消します。ゲームの内容は変わりません。")
                .lineSpacing(InkFont.bodyLineSpacing / 2)
            if let price {
                Text(verbatim: price)
                    .font(InkFont.heading)
                    .monospacedDigit()
            }
            if !app.storeService.isAvailable {
                Text("いまは購入できません(準備中)")
                    .font(InkFont.caption)
                    .foregroundStyle(InkColor.textDim)
            }
            VStack(spacing: 10) {
                Button {
                    Task {
                        busy = true
                        await app.purchaseRemoveAds()
                        busy = false
                        if app.adsRemoved { back() }
                    }
                } label: {
                    Text("購入する")
                }
                .buttonStyle(.ink(.primary))
                Button {
                    Task {
                        busy = true
                        await app.restorePurchases()
                        busy = false
                        if app.adsRemoved { back() }
                    }
                } label: {
                    Text("購入を復元")
                }
                .buttonStyle(.ink(.secondary))
            }
            .disabled(!app.storeService.isAvailable || busy)
            .padding(.bottom, AdLayout.bottomButtonGap)
        }
        .task {
            price = await app.storeService.displayPrice(for: ProductID.removeAds)
        }
    }
}
