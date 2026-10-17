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
                ui("ui.button.back_to_settings")
            }
            .buttonStyle(.ink(.quiet, fill: false))

            ui("ui.body.remove_ads")
                .font(InkFont.heading)
                .tracking(InkFont.headingTracking)
            ui("ui.body.remove_ads_blurb")
                .lineSpacing(InkFont.bodyLineSpacing / 2)
            if let price {
                Text(verbatim: price)
                    .font(InkFont.heading)
                    .monospacedDigit()
            }
            if !app.storeService.isAvailable {
                ui("ui.body.purchase_unavailable")
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
                    ui("ui.button.buy")
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
                    ui("ui.button.restore_purchases")
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
