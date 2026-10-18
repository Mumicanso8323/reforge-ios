import SwiftUI

/// S8 設定。下からの札(InkCard)の中身。右上の角のボタン(SettingsCorner.swift)で開閉する。効果音(MVP は音なし)とプライバシー(P3 で URL)は出さない。
/// 広告を消す画面は札を重ねず、この中身を差し替えて出す。
struct SettingsView: View {
    @Bindable var app: AppModel
    /// 札を閉じる(記録を消した後など)。
    var close: () -> Void
    @State private var showRemoveAds = false
    @State private var restoreMessage: String?
#if DEBUG
    /// 開発の設定(DEBUG のビルドだけ。配る dev の ipa は Release なので出ない。保存には入れない)。
    @AppStorage(GameStore.devHoldClockKey) private var devHoldClock = false
    @AppStorage(PrologueStyle.defaultsKey) private var prologueStyle = PrologueStyle.a.rawValue
    @AppStorage(MapTouchSettings.handKey) private var mapTouchHand = HUDLayout.Hand.right.rawValue
    @AppStorage(MapTouchSettings.directionsKey) private var mapTouchDirections = 8
    @AppStorage(MapTouchSettings.neutralKey) private var mapTouchNeutral = 14
    @AppStorage(MapTouchSettings.tapWalkKey) private var mapTouchTapWalk = false
    @AppStorage(MapTouchSettings.stickPlacementKey) private var mapTouchStickPlacement = false
    @AppStorage(MapTouchSettings.zoomPlanKey) private var mapTouchZoomPlan = MapZoomPlan.b.rawValue
    @AppStorage(MapTouchSettings.autoReturnKey) private var mapTouchAutoReturn = true
#endif

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// 記録を消す(読み込みの失敗の画面でも出す。文は BootText にもあるので表が無くても出る)。
    private var recordsSection: some View {
        InkSection(title: ui("ui.body.records")) {
            InkHoldButton(label: ui("ui.button.delete_save"),
                          hint: ui("ui.body.delete_save_hint")) {
                app.deleteSave()
                close()
            }
            .padding(.top, 10)
            .accessibilityIdentifier("deleteSaveButton")
        }
    }

    var body: some View {
        if app.content == nil {
            // 読み込みの失敗の画面(文言の表が無い)。表を要らない行だけ(BootText で出せる文と、バージョン)。記録は消せる
            VStack(alignment: .leading, spacing: 24) {
                Text(verbatim: version)
                    .font(InkFont.caption)
                    .foregroundStyle(InkColor.textDim)
                recordsSection
            }
        } else if showRemoveAds {
            RemoveAdsView(app: app, back: { showRemoveAds = false })
        } else {
            VStack(alignment: .leading, spacing: 24) {
                // 言語の節(選べる言語が 2 つ以上のときだけ出る。いまは日本語だけなので何も置かない)
                LanguageSection(app: app)

                if AdPolicy.shown {
                    InkSection(title: ui("ui.body.ads")) {
                        if app.adsRemoved {
                            InkRow(title: ui("ui.body.ads_hidden"))
                        } else {
                            Button {
                                showRemoveAds = true
                            } label: {
                                InkRow(title: ui("ui.body.remove_ads"), value: Text(verbatim: "›"))
                            }
                            .buttonStyle(.inkRow)
                            .accessibilityIdentifier("removeAdsButton")
                        }
                        Button {
                            Task {
                                await app.restorePurchases()
                                restoreMessage = app.adsRemoved ? UIText.shared.string("ui.body.restore_done") : UIText.shared.string("ui.body.restore_none")
                            }
                        } label: {
                            InkRow(title: ui("ui.body.restore_purchases"), detail: restoreMessage.map { spokenText($0) })
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
                        Picker("操作棒の利き手", selection: $mapTouchHand) {
                            Text("右").tag(HUDLayout.Hand.right.rawValue)
                            Text("左").tag(HUDLayout.Hand.left.rawValue)
                        }
                        Picker("向きの数", selection: $mapTouchDirections) {
                            Text("8").tag(8)
                            Text("4").tag(4)
                        }
                        Picker("中立の幅", selection: $mapTouchNeutral) {
                            Text("10pt").tag(10)
                            Text("14pt").tag(14)
                            Text("20pt").tag(20)
                        }
                        Toggle("地図のタップですぐ歩く", isOn: $mapTouchTapWalk)
                        Toggle("操作棒をカードの横に置く", isOn: $mapTouchStickPlacement)
                        Picker("拡大の段", selection: $mapTouchZoomPlan) {
                            Text("A").tag(MapZoomPlan.a.rawValue)
                            Text("B").tag(MapZoomPlan.b.rawValue)
                            Text("C").tag(MapZoomPlan.c.rawValue)
                        }
                        Toggle("見回しを自動で戻す", isOn: $mapTouchAutoReturn)
                    }
                }

#endif

                InkSection(title: ui("ui.body.about")) {
                    InkRow(title: ui("ui.body.version"), value: Text(verbatim: version))
                    InkRow(title: ui("ui.body.license"), value: ui("ui.body.license_value"))
                    InkRow(title: ui("ui.body.font"), detail: Text(verbatim: "BIZ UDGothic(SIL Open Font License 1.1)"))
                }

                // 一番下(押し方は今のまま。確かめのダイアログは足さない)
                recordsSection
            }
        }
    }
}
