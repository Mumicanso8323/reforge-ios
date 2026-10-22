import SwiftUI
import UIKit

/// S0 タイトル。絵は 1 枚(Resources/Art/title-art.png。ネタバレの無い公開の絵)。
/// 上 1/3 に題、下 1/4 にボタン。絵が無いときは墨の地だけで出す。
struct TitleView: View {
    @Bindable var app: AppModel
    /// 「セーブから読む」の一覧の札を開いているか。
    @State private var loadOpen = false

    var body: some View {
        ZStack {
            InkColor.prologueGround.ignoresSafeArea()
            if let art = UIImage(named: "title-art") {
                // 絵は画面の幅と高さで切る(縦横比が画面と違うと、scaledToFill の絵が画面の外へはみ出すため)
                Color.clear
                    .overlay(Image(uiImage: art).resizable().scaledToFill())
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                // 空が明るいので、題の文字が読めるように全体を一段沈める(平らな色で。グラデーションは使わない)
                InkColor.prologueGround.opacity(0.45).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                Spacer().frame(height: 72)
                Text(verbatim: "Re:Forge")
                    .font(InkFont.display)
                    .tracking(InkFont.displayTracking)
                    .foregroundStyle(InkColor.text)
                ui("ui.body.title_tagline")
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.textDim)
                    .padding(.top, 8)
                Spacer()
                VStack(spacing: 10) {
                    if app.hasResume {
                        Button {
                            app.continueGame()
                        } label: {
                            ui("ui.button.continue")
                        }
                        .buttonStyle(.ink(.primary))
                        .accessibilityIdentifier("continueButton")
                        // いまの記録を消すので、確かめのダイアログの代わりに長押しにする
                        InkHoldButton(label: ui("ui.button.new_game"), hint: ui("ui.a11y.new_game_hint"), showsHint: false, confirmID: "title.newGame") {
                            app.startNewGame()
                        }
                        .accessibilityIdentifier("newGameButton")
                    } else {
                        Button {
                            app.startNewGame()
                        } label: {
                            ui("ui.button.new_game")
                        }
                        .buttonStyle(.ink(.primary))
                        .accessibilityIdentifier("newGameButton")
                        // 中断の枠が無い・読めないとき、自動か手動の枠があれば、そこから読める
                        if app.hasSavePoints {
                            Button {
                                loadOpen.toggle()
                            } label: {
                                ui("ui.button.load_from_title")
                            }
                            .buttonStyle(.ink(.secondary))
                            .accessibilityIdentifier("loadFromTitle")
                        }
                    }
                }
                .frame(maxWidth: 280)
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkCard(isPresented: $loadOpen, title: ui("ui.button.load_from_title")) {
            SavePointSections(groups: app.savePointGroups()) { slot in
                loadOpen = false
                app.loadFromTitle(slot)
            }
        }
    }
}
