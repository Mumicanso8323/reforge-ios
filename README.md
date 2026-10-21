# Re:Forge (iOS)

ターミナル版ゲーム「Re:Forge」を iPhone 向けに SwiftUI で作り直すリポジトリです。

**どんなゲームか**: 火を起こし、材料を集めて道具や設備を作り、仲間に頼んで運ばせ、地図を少しずつ広げていく工業のゲームです。遊ぶうちに、物語が後でひっくり返ります。
昼はリアルタイムで進み、夜は作業を選ぶか、寝て朝まで飛ばすかを選びます。アプリを閉じている間は進みません。
失敗したら「はじめから / 記憶を持って巻き戻す / 失って続ける / セーブから読む」の 4 つから選べます。

## 構成

- `ReForge/` — アプリ(SwiftUI、iOS 17 以上)。画面は本体が作る `Frame` を描くだけです。広告はなく、最初の部分は無料で、本編の残りは 1 回の購入で解放します。
  - 画面の固定文言は `ui("ui.<区分>.<名前>")` で文言の表(`content/public/text/ja/app*.json`)から引きます。`Text("…")` のリテラルは書きません。確かめは `python3 tools/check-app-strings.py` です(CI が見ます)。
- `ReForgeCore/` — Swift パッケージ。UIKit / SwiftUI に依存せず Linux でもテストできます。モジュールは層に分かれています(`RFKernel` → 地図・物質・文言の書式 → 世界状態とコンテンツ → 規則と認識 → 各システム → シミュレーション・保存・画面向けの組み立て)。正本は `docs/architecture/A-modules.md`。乱数は seed 固定で、同じ入力から同じ結果になります。
- `content/public/` — 公開の試験用コンテンツ(物語を含まない最小の集まり)。本物のコンテンツは非公開の層で、ビルドのときに封をしてアプリに入れます。
- `tools/` — 確かめの道具(`check-app-switches.py`・`check-app-names.py`・`check-public-spoilers.py`・`check-store-metadata.py`・`check-app-strings.py`・`check-languages.py`)。
- `store/` — ストアの原稿の置き場(言語ごと)。
- `docs/` — 設計(`architecture/` の A〜G)と、作業の説明書(`briefs/`)。
- `project.yml` — XcodeGen の定義。`.xcodeproj` はコミットせず、生成して使います。

保存は端末内(Application Support/reforge/)の JSON で、中断の枠・夜明けの自動の枠(直近 3 日)・手動の枠(3 つ)があります(`docs/architecture/D-save.md`)。

## テスト

```sh
# Linux(Docker)でも Mac でも同じ
swift test --package-path ReForgeCore
docker run --rm -v "$PWD":/w -w /w swift:6.1-noble swift test --package-path ReForgeCore
```

モジュールごとの単体テストと、ボットが遊んで確かめる受け入れテスト(`Tests/AcceptanceTests`)が入っています。非公開の層があれば、環境変数 `REFORGE_PRIVATE_CONTENT` で重ねて回します。

## ビルド(CI)

Mac は無くても GitHub Actions(`.github/workflows/ci.yml`)でビルドできます。

- `main` への push / PR で自動実行: Linux で `swift test`(ReForgeCore)→ macOS でシミュレータの単体テストと未署名 ipa の作成(Artifacts に残ります)。
- Actions タブ → ci → Run workflow で `release` にチェックすると、ipa を添付したプレリリースを作ります。

Mac が手元にある場合:

```sh
brew install xcodegen
xcodegen generate
open ReForge.xcodeproj
```

## インストール(SideStore)

1. [Releases](https://github.com/Mumicanso8323/reforge-ios/releases) から最新の `ReForge.ipa` を iPhone にダウンロードします。
2. SideStore の「My Apps」で「+」を押し、ダウンロードした ipa を選びます。SideStore が自分の Apple ID で署名して入れます。
3. 無料 Apple ID の署名は 7 日で切れるので、SideStore で定期的に Refresh してください。

## ライセンス

ライセンスは未定です。ライセンス表記が無いため、現時点ではすべての権利を留保します(All rights reserved)。
