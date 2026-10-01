import SwiftUI

/// S8 設定。効果音(MVP は音なし)とプライバシー(P3 で URL)は出さない。
struct SettingsView: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var showRemoveAds = false
    @State private var restoreMessage: LocalizedStringKey?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if app.adsRemoved {
                        Text("広告は非表示です")
                    } else {
                        Button("広告を消す") { showRemoveAds = true }
                            .accessibilityIdentifier("removeAdsButton")
                    }
                    Button("購入を復元") {
                        Task {
                            await app.restorePurchases()
                            restoreMessage = app.adsRemoved ? "購入を復元しました" : "復元できる購入はありません"
                        }
                    }
                    .accessibilityIdentifier("restoreButton")
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("広告")
                }

                Section {
                    Button("記録を消す", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("記録")
                }

                Section {
                    LabeledContent {
                        Text(verbatim: version)
                    } label: {
                        Text("バージョン")
                    }
                    LabeledContent {
                        Text("すべての権利を留保")
                    } label: {
                        Text("ライセンス")
                    }
                    LabeledContent {
                        Text("BIZ UDGothic(SIL Open Font License 1.1)")
                    } label: {
                        Text("フォント")
                    }
                } header: {
                    Text("このアプリについて")
                }
            }
            .navigationTitle(Text("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("記録を消しますか?", isPresented: $confirmDelete) {
                Button("消す", role: .destructive) {
                    app.deleteSave()
                    dismiss()
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("いまの状態とセーブ地点がすべて消えます。元には戻せません。")
            }
            .sheet(isPresented: $showRemoveAds) {
                RemoveAdsSheet(app: app)
            }
        }
    }
}
