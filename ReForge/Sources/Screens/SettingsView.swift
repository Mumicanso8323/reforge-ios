import SwiftUI

/// S8 設定。下からの札(InkCard)の中身。右上の角のボタン(SettingsCorner.swift)で開閉する。効果音(MVP は音なし)とプライバシー(P3 で URL)は出さない。
/// 広告を消す画面は札を重ねず、この中身を差し替えて出す。
struct SettingsView: View {
    @Bindable var app: AppModel
    /// 札を閉じる(記録を消した後など)。
    var close: () -> Void
    @State private var showRemoveAds = false
    @State private var restoreMessage: LocalizedStringKey?
#if DEBUG
    /// 開発の設定(DEBUG のビルドだけ。配る dev の ipa は Release なので出ない。保存には入れない)。
    @AppStorage(GameStore.devHoldClockKey) private var devHoldClock = false
    @AppStorage(PrologueStyle.defaultsKey) private var prologueStyle = PrologueStyle.a.rawValue
#endif

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        if showRemoveAds {
            RemoveAdsView(app: app, back: { showRemoveAds = false })
        } else {
            VStack(alignment: .leading, spacing: 24) {
                // 言語の節の場所(L-10b で作る。いまは空けておくだけ)
                if AdPolicy.shown {
                    InkSection(title: Text("広告")) {
                        if app.adsRemoved {
                            InkRow(title: Text("広告は非表示です"))
                        } else {
                            Button {
                                showRemoveAds = true
                            } label: {
                                InkRow(title: Text("広告を消す"), value: Text(verbatim: "›"))
                            }
                            .buttonStyle(.inkRow)
                            .accessibilityIdentifier("removeAdsButton")
                        }
                        Button {
                            Task {
                                await app.restorePurchases()
                                restoreMessage = app.adsRemoved ? "購入を復元しました" : "復元できる購入はありません"
                            }
                        } label: {
                            InkRow(title: Text("購入を復元"), detail: restoreMessage.map { Text($0) })
                        }
                        .buttonStyle(.inkRow)
                        .accessibilityIdentifier("restoreButton")
                    }
                }

#if DEBUG
                if GameStore.devSettingsAvailable {
                    InkSection(title: Text("開発")) {
                        if let summary = app.game?.slowStepSummary {
                            InkRow(title: Text("重い歩み"), value: Text(verbatim: summary))
                        }
                        Toggle(isOn: $devHoldClock) {
                            Text("設計とノートを開いている間、時計を止める")
                        }
                        .accessibilityIdentifier("devHoldClockToggle")
                        .padding(.top, 10)
                        // 序の見せ方の 3 案(PT-B6)。次に序を見るとき(はじめから)に効く
                        Picker(selection: $prologueStyle) {
                            Text("1 行ずつ").tag(PrologueStyle.a.rawValue)
                            Text("1 字ずつ").tag(PrologueStyle.b.rawValue)
                            Text("場面ごと").tag(PrologueStyle.c.rawValue)
                        } label: {
                            Text("序の見せ方")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("devPrologueStylePicker")
                        .padding(.top, 10)
                    }
                }

#endif

                InkSection(title: Text("このアプリについて")) {
                    InkRow(title: Text("バージョン"), value: Text(verbatim: version))
                    InkRow(title: Text("ライセンス"), value: Text("すべての権利を留保"))
                    InkRow(title: Text("フォント"), detail: Text("BIZ UDGothic(SIL Open Font License 1.1)"))
                }

                // 一番下(押し方は今のまま。確かめのダイアログは足さない)
                InkSection(title: Text("記録")) {
                    InkHoldButton(label: Text("記録を消す"),
                                  hint: Text("長押しで、いまの状態とセーブ地点をすべて消します。元には戻せません。")) {
                        app.deleteSave()
                        close()
                    }
                    .padding(.top, 10)
                    .accessibilityIdentifier("deleteSaveButton")
                }
            }
        }
    }
}
