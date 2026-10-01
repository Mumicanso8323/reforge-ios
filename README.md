# Re:Forge (iOS)

ターミナル版ゲーム「Re:Forge」を iPhone 向けに SwiftUI で作り直すリポジトリです。いまは骨組みだけで、ゲームの中身はこれから入れます。

## 構成

- `ReForge/` — アプリ本体(SwiftUI、iOS 17 以上)。上下に 50pt の広告枠を確保した共通コンテナの中に全画面を置きます(広告 SDK はまだ入れていません。DEBUG ビルドだけ枠を表示)。
- `ReForgeCore/` — ゲームロジック(純 Swift のパッケージ。UIKit / SwiftUI に依存せず Linux でもテストできる)。時間の進み方は `GameClock` プロトコルの裏に隠してあり、ターン制/リアルタイムを差し替えられます。
- `project.yml` — XcodeGen の定義。`.xcodeproj` はコミットせず、生成して使います。

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

ReForgeCore だけなら Linux / Mac で `swift test --package-path ReForgeCore`。

## インストール(SideStore)

1. [Releases](https://github.com/Mumicanso8323/reforge-ios/releases) から最新の `ReForge.ipa` を iPhone にダウンロードします。
2. SideStore の「My Apps」で「+」を押し、ダウンロードした ipa を選びます。SideStore が自分の Apple ID で署名して入れます。
3. 無料 Apple ID の署名は 7 日で切れるので、SideStore で定期的に Refresh してください。

## ライセンス

ライセンスは未定です。ライセンス表記が無いため、現時点ではすべての権利を留保します(All rights reserved)。
