# Re:Forge (iOS)

ターミナル版ゲーム「Re:Forge」を iPhone 向けに SwiftUI で作り直すリポジトリです。いまは Phase 1(縦切りの遊べる版)です。

**遊べること**: 5 人の拠点で 30 日生き延び、井戸・簡易農場・基礎炉を建てて拠点を自立させる 1 本。
昼(180 秒)はリアルタイムで進み、採取・製作・建造を 10 行動まで。日が沈んだら、焚き火台があれば夜作業(4 行動)をするか、寝て朝まで飛ばすか。
アプリを閉じている間は拠点は進みません。食料が尽きて 5 日、または水が尽きて 3 日でゲームオーバーになり、
「最初からやり直す / 記憶を持ったまま巻き戻す / 失って続ける / 最後の記録から読み込む」の 4 つから選べます。

## 構成

- `ReForge/` — アプリ本体(SwiftUI、iOS 17 以上、標準部品のみ)。上下に高さ 50pt の広告枠(いまはダミーの灰色の枠)を確保した共通コンテナの中に全画面を置きます。購入(広告除去)は枠だけで、StoreKit はまだ入れていません。
  - 画面の固定文言は補間なしのリテラルで書き、`ReForge/Resources/Localizable.xcstrings` に集めます。ソースを変えたら `python3 tools/gen-xcstrings.py` でカタログを作り直してください(テストが抜けを検出します)。数や名前が入る文は ReForgeCore の `GameText` で組み立てます。
- `ReForgeCore/` — Swift パッケージ。UIKit / SwiftUI に依存せず Linux でもテストできます。
  - `ReForgeCore` — ゲームロジック。状態は値型 `GameState`、規則は `Game`。時間(`TimeModel`)・失敗の代償(`FailurePolicy`)・オフライン(`OfflinePolicy`)はプロトコルの裏にあり、仮値や方針を差し替えられます。乱数は seed 固定の SplitMix64 で、同じ入力から同じ結果になります。
  - `ReForgeContent` — 原作のコンテンツ JSON から MVP で使う項目だけをそのまま抜き出したものと、MVP 用の差し替え(`mvp-overrides.json`)。
- `project.yml` — XcodeGen の定義。`.xcodeproj` はコミットせず、生成して使います。

保存は端末内(Application Support/reforge/)の JSON で、いまの状態(行動のたびに保存)とセーブ地点(新規開始・毎朝・手動セーブ)の 2 つです。

## テスト

```sh
# Linux(Docker)でも Mac でも同じ
swift test --package-path ReForgeCore
docker run --rm -v "$PWD":/w -w /w swift:6.1-noble swift test --package-path ReForgeCore
```

ロジックの受け入れテスト(初期状態・各行動の増減・昼夜の消費と生産・餓死/脱水・勝利・100 seed の自動走行での成立性・保存・禁止語の点検・原作との突き合わせ・失敗後の 4 方針)が入っています。

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
