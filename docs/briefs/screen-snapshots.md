# 説明書: 画面の写真(CI のシミュレータで主な画面を 5 言語で撮る)

作業の単位: 「画面の写真」(W-07 の描画より前)。実装: relay:codex-impl。受け取り: 統合担当(architect)。

## 1. 目的

Linux の機械では誰もアプリの画面を見ていない。iOS の CI のシミュレータで、主な画面を 5 つの言語で撮って PNG を artifact に上げ、
文字が枠から出る・切れるを見つけたら CI を止める。実機の代わりにはならないが、「誰も画面を見ていない」状態から前に進める。

- 撮る画面(8): 地図 / 下からの札(足元の札) / 設計 / 拠点 / 仲間 / 研究 / ゲームオーバー(4 択) / 設定
- 言語(5): `ja` / `en` / `zh-Hans` / `zh-Hant` / `ko`
- 書体は言語で変わる(`ReForge/Sources/Theme/InkFont.swift` の `InkFont.setLanguage`・`family(for:)`。地図は言語によらず BIZ UDGothic)。
- 訳はまだ無い。ja 以外の言語でも日本語のキーがそのまま出る(カタログの既定)。それでも書体と枠の確かめにはなる。訳が入ったら同じ仕組みで撮り直せる。

## 2. 絶対に守ること(ネタバレ・公開)

公開リポジトリの Actions の artifact は誰でも見られる。**撮るのは公開の層(`content/public`。試験用のコンテンツ)だけ。**

1. 撮るジョブは新しいジョブ `screens` にし、**非公開のコンテンツを取り込まない**(`actions/checkout` で `reforge-content` を取らない。`REFORGE_CONTENT_DEPLOY_KEY` を使わない)。
2. そのジョブでは `tools/content/stage.sh` を非公開の層なしで回す(`content/private` が無いので、鍵 nil・`private.sealed` なしの束になる)。
3. 二重の守り: 撮る前に、アプリの中で `ContentKey.key == nil` かつ束に `private.sealed` が無いことを確かめ、どちらかがあれば**撮らずに失敗**する(UI テストで assert)。
4. artifact に上げるのは PNG と、検査の結果の小さな JSON だけ。ログ(test.log など)は上げない。
5. 既存の `ios` ジョブ(非公開の層を取り込む)には、撮る処理を入れない。

## 3. 作るもの

### 3.1 撮るための起動の形(アプリ。`#if DEBUG` の中だけ)
- 新しいファイル `ReForge/Sources/Debug/ScreenshotMode.swift`(`#if DEBUG` で全体を囲む)。
- 起動引数 `-ReForgeScreenshot <画面>`(`map`・`foot`・`design`・`base`・`crew`・`research`・`gameOver`・`settings`)で起動したら:
  - 公開の層の束で、固定の種(例 `seed = 1`)の新しい世界を作る(`GameBootstrap.newWorld`)。
  - 画面の要素の解放(U18 の `UIGateDef`・`Frame.ui`)を**全部開いた**状態で出す(撮るためだけの上書き。保存しない・世界状態を変えない形で。例: `GameStore` に DEBUG だけの `forceAllUIOpen` を足し、`ui.isOpen` がそれを見る)。
  - 時計は止める(同じ絵になるように)。
  - 指定の画面を開く(タブを選ぶ / 足元の札を出す / 研究は拠点のタブの研究の節までスクロール / ゲームオーバーは `runEnded` を真にして 4 択を出す / 設定は設定の札を開く)。
- 言語は起動引数 `-AppleLanguages (xx)` と `-AppleLocale xx` で与える。`InkFont.language` の初期値は `Locale.preferredLanguages.first`。
- 触ってよいアプリのファイル: `ReForge/Sources/Debug/`(新規)、`ReForge/Sources/ReForgeApp.swift`(起動引数を見て ScreenshotMode に渡す数行だけ)、`ReForge/Sources/Game/GameStore.swift`(`#if DEBUG` の上書きを数行)、`ReForge/Sources/Game/GameScreen.swift`(最初のタブを外から決める数行)。ほかの画面のファイル・`Theme/` の既存のファイルは直さない(3.3 の新しいファイルを足すのは可)。

### 3.2 UI テストのターゲット
- `project.yml` に `ReForgeUITests`(`type: bundle.ui-testing`、`platform: iOS`、`dependencies: - target: ReForge`)と、撮るためだけのスキーム `ReForgeScreens`(test に `ReForgeUITests` だけ)を足す。既存のスキーム `ReForge` のテストには入れない(普段の単体テストを遅くしない)。
- `ReForgeUITests/ScreenSnapshotTests.swift`: 言語 × 画面の 40 枚を撮る。1 枚ごとにアプリを起動し直す(`XCUIApplication().launchArguments`)。
  - 撮り方: `XCUIScreen.main.screenshot()` を `XCTAttachment`(`lifetime = .keepAlways`、名前は `<言語>_<画面>`)にする。
  - CI の側で `xcrun xcresulttool export attachments --path <xcresult> --output-path screens/` を使って PNG に出す(Xcode 16 以降)。名前で並ぶようにする。
- 端末は iPhone の 1 機種で固定(CI の既存の選び方と同じく、使える最初の iPhone。機種名を JSON に書く)。

### 3.3 止める検査(できる範囲で)
撮るだけでは止めない。次を検査にし、1 つでも当たれば UI テストを失敗にする。どの言語のどの画面のどの要素かを、**要素の識別子とテキストの長さだけ**で報告する(テキストそのものは出してよい。公開の層の試験用の文言だけなので)。

1. **画面の外に出る**: `app.descendants(matching: .any)` の見えている要素(`isHittable` または `exists` で frame が空でない)の `frame` が、画面(`app.windows.firstMatch.frame`)の外にはみ出していない。
2. **切れる(省略記号)**: SwiftUI の `Text` が切れたかは XCUI から見えないので、アプリの側で測る。新しいファイル `ReForge/Sources/Theme/InkFitCheck.swift`(`#if DEBUG`)に、撮るときだけ有効な修飾子 `.inkFitCheck(id:)` を作る:
   - 要素の文字列の「理想の大きさ」(`fixedSize` で測った幅・高さ)と、実際に置かれた大きさを `GeometryReader` で比べ、理想が実際より大きければ、その要素の `accessibilityValue` を `"overflow"` にする。
   - Theme の部品(`InkRow` の題と値、`.ink` のボタンの文言、`InkPanel` の見出し、帯の値)に、**撮る起動のときだけ**この修飾子が掛かるよう、Theme の既存のファイルには 1 行ずつだけ足す(art-director に知らせる)。
   - UI テストは `accessibilityValue == "overflow"` の要素があれば失敗にする。
3. **重なり**: 下のタブの帯と、上の状態の帯の frame が、パネルの見出しの frame と重ならない。
4. 失敗しても PNG は上げる(`if: always()`)。結果は `screens/report.json`(言語・画面・当たった要素の id と種類)。

検査が誤って当たる(たとえば地図の 1 マスの記号)なら、その要素を検査から外す一覧を UI テストの中に 1 か所で持つ(理由をコメントで)。

### 3.4 CI のジョブ
- `.github/workflows/ci.yml` に新しいジョブ `screens`:
  - `runs-on: macos-26`、`needs: [core, app-switches]`、`timeout-minutes: 60`
  - 起動: `push` の main と、`workflow_dispatch` の新しい入力 `screens`(boolean、既定 true)。
  - 手順: checkout(公開のリポジトリだけ) → Xcode の選択(既存と同じ) → `tools/content/stage.sh`(非公開なし) → `xcodegen generate` → シミュレータを選ぶ → `xcodebuild test -scheme ReForgeScreens -resultBundlePath screens.xcresult CODE_SIGNING_ALLOWED=NO` → `xcresulttool export attachments` → `actions/upload-artifact`(名前 `screens`、`screens/*.png` と `screens/report.json`、`if: always()`、保持 14 日)。
- **既存の `ios` ジョブ・release の手順・release の名前とタグ(`dev`)・ファイル名(`ReForge.ipa`)は変えない**(オーナーのショートカットが固定の URL を取る)。

## 4. 約束(全単位と同じ。F §4)
- 公開リポジトリに物語の語を書かない(コード・コメント・コミットのメッセージ)。
- 文字列: 画面の固定文言を新しく足すなら `Text("…")`。撮るための DEBUG の文言は足さない(要らないはず)。
- 保存に触らない(撮る起動は保存を読まない・書かない。`FileSaveStorage` に書かないこと)。
- `content/private`・`content/public` のファイルを変えない。
- アプリの switch・型の名前・文字列カタログの 3 つの確かめを通す。

## 5. 確かめのコマンド(Linux の作業場で回せるもの)

この作業場は Linux で、Xcode もシミュレータも無い。アプリと UI テストはコンパイルできないので、次を通したうえで、実際の確かめは CI に任せる。

```
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/gen-xcstrings.py --check
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
python3 -c "import yaml; yaml.safe_load(open('project.yml'))"
docker run --rm -v "$PWD":/w -w /w swift:6.1-noble swift test --package-path ReForgeCore   # 本体を触っていなければ省略可
```

- Swift の文法は目で確かめる(`#if DEBUG` の囲み、`@MainActor`、XCUI の API 名)。存在の怪しい API(`xcresulttool export attachments` のフラグなど)は、Apple の文書のどの版の何かをコミットのメッセージに書く。
- 非公開の層を重ねた物語の語の検査は、統合担当がマージのときに回す。

## 6. 受け入れ(統合担当と CI で見る)
1. `screens` ジョブが緑で、artifact `screens` に 40 枚の PNG(`ja_map.png` … `ko_settings.png`)と `report.json` がある。
2. `screens` ジョブのログと artifact に、非公開の層の文が写っていない(撮る前の assert が通っている)。
3. わざと 1 つの `InkRow` の題を長くした枝で回すと、`overflow` で失敗する(確かめたら元に戻す。コミットには入れない)。
4. 既存の `ios` ジョブの結果と release の手順が変わっていない。

## 7. 終わりの報告(architect へ)
- 入れたコミットのハッシュと、触ったファイルの一覧
- 撮る起動の引数と、全部開いた状態の作り方(どこに何を足したか)
- 検査から外した要素の一覧と理由
- Linux で確かめられなかったこと(API の名前・フラグ)と、その根拠の出典
- CI で最初に見るべき所
