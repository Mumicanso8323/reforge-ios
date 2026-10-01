import SwiftUI

/// S11 広告除去。価格はストアから取る(ハードコードしない)。P1 は購入できない。
struct RemoveAdsSheet: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var price: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("上下の広告を消します。ゲームの内容は変わりません。")
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                if let price {
                    Text(verbatim: price)
                        .font(.title2.bold())
                }
                if !app.storeService.isAvailable {
                    Text("いまは購入できません(準備中)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    Button {
                        Task {
                            busy = true
                            await app.purchaseRemoveAds()
                            busy = false
                            if app.adsRemoved { dismiss() }
                        }
                    } label: {
                        Text("購入する").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Task {
                            busy = true
                            await app.restorePurchases()
                            busy = false
                            if app.adsRemoved { dismiss() }
                        }
                    } label: {
                        Text("購入を復元").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .disabled(!app.storeService.isAvailable || busy)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, AdLayout.bottomButtonGap)
            .navigationTitle(Text("広告を消す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                price = await app.storeService.displayPrice(for: ProductID.removeAds)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
