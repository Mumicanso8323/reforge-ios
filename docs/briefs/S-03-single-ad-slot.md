# 説明書 S-03: 広告の枠を下の 1 つにする

作業の単位: 収益の画面の直し(リーダーの決め。オーナーにはリーダーが伝える)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: なし。土台: integration-c の先頭。
アプリは macOS の CI でしかコンパイルされない。Linux では確かめられないので、API の名前と型は目で確かめる。

## 1. 目的
今は画面の上と下の 2 か所に、高さ 50pt の広告の枠がある(`ReForge/Sources/Monetization/AdSlot.swift` の `AdBannerContainer`)。小さい画面で地図を削るので、**下の 1 つだけ**にする。上の枠の分の高さは、中身(地図の画面では地図)に回す。

## 2. 直すこと
1. `AdBannerContainer`: 上の `AdSlot(position: .top)` を出さない。下の枠は今のまま(高さ 50pt を読み込み前から確保し、失敗しても畳まない。広告を消す購入で 0 に畳む)。
2. `AdSlotPosition`: `.top` を消し、使っている所を直す(`accessibilityIdentifier` は下の `adSlotBottom` だけになる)。`adSlotTop` を使っている UI テストがあれば直す。
3. 上の安全域: 上の枠が無くなると、中身が画面の上の端(ノッチ・Dynamic Island の下)に近づく。今 `GameScreen` と `TitleView` が `.padding(.vertical, AdLayout.contentGap)` を付けているので、上は**安全域(safe area)の内側に**中身が収まることを確かめる(`AdBannerContainer` が安全域を無視していないか見る。無視していたら上だけ安全域を守る)。右上の 52x52pt は設定のボタン(L-10)のために空けておく約束(art-director 0ad0847)なので、そこに何も動いてこないこと。
4. `AdLayout` の注記と、`GameScreen.swift` の冒頭のコメント(「広告枠は … 上下に確保する」)を「下に 1 つ」に直す。
5. 文書: `README.md` の 12 行目の「上下に高さ 50pt の広告枠」を「下に高さ 50pt の広告枠 1 つ」に直す。`docs/architecture/` に広告の枠の数と場所を書いた所があれば同じく直す(`grep -rn "広告" docs README.md` で探す)。設計の計画の文書(reforge-plan)は統合担当が直すので触らない。
6. 画面の写真の UI テスト(`ReForgeUITests/ScreenSnapshotTests.swift`)が上の枠の高さや識別子を前提にしていれば直す。

## 3. 確かめ
```
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 tools/gen-xcstrings.py --check     # 「広告」の文字が 1 か所減っても、キーは同じなので変わらないはず
```
- 本体(`ReForgeCore/`)には触らないので swift test は要らない。本番の確かめは、リーダーが回す macOS の CI(iOS のジョブと screens のジョブ)。

## 4. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForge/Sources/Monetization/AdSlot.swift`、`ReForge/Sources/Game/GameScreen.swift`(コメントと、3 の安全域のために要るときの余白だけ)、`ReForge/Sources/Screens/TitleView.swift`(同じ)、`ReForge/Sources/ReForgeApp.swift`(`AdBannerContainer` の呼び方が変わるときだけ)、`ReForgeUITests/`、`README.md`、`docs/architecture/`(広告の枠の記述だけ)。
- 触らない: `ReForgeCore/`・`content/`・購入の仕組み(`StoreService`・`RemoveAdsView` の文言)・CI の release の名前・タグ・ipa の名前。

## 5. 約束
- 公開リポジトリに物語の語を書かない。アプリに新しい日本語のリテラルを足さない。
- コミットのメッセージの末尾は、渡された 2 行の trailer。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(F §4)。
- 枝の名前・先頭のハッシュ・3 の結果・安全域をどう確かめたか(コードのどこを見たか)。
