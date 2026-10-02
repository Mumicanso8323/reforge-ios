import SwiftUI
import UIKit

/// S0 タイトル。絵は 1 枚(Resources/Art/title-art.png。ネタバレの無い公開の絵)。
/// 上 1/3 に題、下 1/4 にボタン。絵が無いときは墨の地だけで出す。
struct TitleView: View {
    @Bindable var app: AppModel

    var body: some View {
        ZStack {
            InkColor.ground.ignoresSafeArea()
            if let art = UIImage(named: "title-art") {
                // 絵は画面の幅と高さで切る(縦横比が画面と違うと、scaledToFill の絵が画面の外へはみ出すため)
                Color.clear
                    .overlay(Image(uiImage: art).resizable().scaledToFill())
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                // 空が明るいので、題の文字が読めるように全体を一段沈める(平らな色で。グラデーションは使わない)
                InkColor.ground.opacity(0.45).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                Spacer().frame(height: 72)
                Text(verbatim: "Re:Forge")
                    .font(InkFont.display)
                    .tracking(InkFont.displayTracking)
                    .foregroundStyle(InkColor.text)
                Text("素材から、作り直す")
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.textDim)
                    .padding(.top, 8)
                Spacer()
                VStack(spacing: 10) {
                    if app.hasResume {
                        Button {
                            app.continueGame()
                        } label: {
                            Text("つづきから")
                        }
                        .buttonStyle(.ink(.primary))
                        .accessibilityIdentifier("continueButton")
                        // いまの記録を消すので、確かめのダイアログの代わりに長押しにする
                        InkHoldButton(label: Text("はじめから"), hint: Text("長押しで、いまの記録を消してはじめる")) {
                            app.startNewGame()
                        }
                        .accessibilityIdentifier("newGameButton")
                    } else {
                        Button {
                            app.startNewGame()
                        } label: {
                            Text("はじめから")
                        }
                        .buttonStyle(.ink(.primary))
                        .accessibilityIdentifier("newGameButton")
                    }
                }
                .frame(maxWidth: 280)
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
