# 説明書 W-18: 時刻の色(本体)

作業の単位: 序盤 W-18(設計: reforge-plan `docs/plans/2026-10-02-opening-and-industry-depth.md` v0.7 以降の §6.7・INV-O16・INV-O17・TEST-O23・VIS-08)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: W-02b(火床の灯りの半径。integration-c に入っている `Hearths.lightRadius`)。土台: integration-c の先頭。
画面の側(地図の描画で色を使う・帯の目印)は W-19(art-director と地図の描画の担当)。この単位は**本体だけ**で、アプリには触らない。

## 1. 目的
時計から、地図の地形の層の明るさと色味を、本体の純関数で作る。夜明け・昼・夕方・夜の目印の点の間を直線でつなぎ、昼を 64 段に刻む。帯の言葉(目印)と色味は同じ関数から作る(INV-O16)。夜は灯りの円の中だけを明るく描き、円の縁を 1 マスぼかす。

## 2. 作るもの

### 2.1 RFContent: 目印の表(`Schema/` に新しいファイル `TimeTint.swift`)
```swift
public struct TimeTintKey: Codable, Equatable, Sendable {
    public var at: Int              // 夜明けからの分(0...1560。昼 0〜480、夜 480〜1560)。1 日の長さは今の時計の決まりから
    public var mark: TimeMark       // この点から次の点までの帯の言葉
    public var brightness: Int      // ‰。昼は地形の明るさ、夜は灯りの円の中の明るさ
    public var outside: Int?        // ‰。夜の灯りの外の既知の地形の明るさ(省略は 150)。昼は使わない
    public var tint: [Int]          // 重ねる色 [r,g,b](0...255)。色味なしは強さ 0 にする
    public var strength: Int        // ‰(重ねる強さ。上限 350)
}
public struct TimeTintDef: Codable, Equatable, Sendable { public var keys: [TimeTintKey] }
```
- `TimeMark`(`dawn`・`day`・`evening`・`night`)は RFContent に置く(RFPresent から使う。設計の §6.7.5 は RFPresent と書いているが、表の型が要るので下の層に置く)。
- `ContentDB` に `public var timeTint: TimeTintDef?`。読み込みは 1 つの値(後の層が勝つ。`clock` と同じ扱い)。JSON のキーは `"timeTint"`。
- 公開の層の `content/public/world.json` に、設計の §6.7.1 の表どおりの点を入れる(夜明け 0・朝 90・昼 240・夕方 360・日没 480・夜 540〜1470・夜明け前 1560。夜明け前の `outside` は 400、夜の点の `outside` は 150)。数は art-director が後で詰める。
- 1 日の分の長さ(昼 480・夜 1080)は、今の時計の定義(`ClockDef` の `dayGameHours`・`nightGameHours`)から求め、表の `at` の上限はその和にする。
- 検証(`ContentValidator` に `timeTintWellFormed`): 点が 2 つ以上・`at` が昇順で 0 から始まり 1 日の長さで終わる・‰ が 0...1000・`strength` ≤ 350・`tint` が 3 つで 0...255。**色味の色が予約の赤に入らない**(INV-O17。予約の赤の判定は art-director の決まり `docs/art/README.md` の「予約の赤」と同じ式を RFPresent の `Palette` から使う。判定の関数が無ければ、色相 0°±18° かつ彩度 50% 以上を予約とし、関数を `Palette` に足す)。
- `timeTint` が無いコンテンツ(古いデータ)では、今の見え方(昼 1000‰・夜 750‰・色味なし・夜の外は今の `remembered`)を返す既定の表を使う(2.2)。

### 2.2 RFPresent: 補間(新しいファイル `TimeOfDay.swift`)
```swift
public struct TimeTint: Equatable, Hashable, Sendable {
    public var brightness: Int      // ‰(灯りの中・昼の地形)
    public var outside: Int         // ‰(夜の灯りの外の既知の地形)
    public var tint: RGB
    public var strength: Int        // ‰
    public var step: Int            // 刻みの番号(描画の記憶の鍵)
    /// 地形の色に、明るさ(‰)と色味を掛けた色。整数だけで計算する(浮動小数を使わない)。
    public func apply(_ base: RGB, brightness: Int) -> RGB
}
public enum TimeOfDay {
    /// 1 日の中の位置(夜明けからの分)から刻みの番号。7.5 分で 1 段(昼 64 段・夜 144 段)。
    public static func step(minutes: Int) -> Int
    public static func mark(minutes: Int, _ def: TimeTintDef) -> TimeMark
    public static func tint(minutes: Int, _ def: TimeTintDef) -> TimeTint
    public static let defaultDef: TimeTintDef   // 2.1 の最後の「古いデータの既定」
}
```
- 補間は**刻みの先頭の分**で行う(同じ段なら同じ値)。隣の 2 点の間を、`brightness`・`outside`・`strength` と色味の各成分を、それぞれ整数で直線補間(四捨五入は `(a * (d - t) + b * t + d / 2) / d` の形)。
- `mark` は、その刻みの先頭の分を含む区間の、始まりの点の `mark`(色味と同じ区間から作る。INV-O16)。
- `apply`: `out = base × brightness / 1000` を作り、`out` と `tint × brightness / 1000` を `strength / 1000` の割合で混ぜる。各成分 0...255 に収める。
- 今の `RGB.scaled(_ k: Double)` は残す(ほかで使っている)。新しい計算では使わない。

### 2.3 RFPresent: Frame と地図
- `ClockView` に `public var minutesSinceDawn: Int`(時計の `now - dayStartedAt` を分にしたもの。夜は日没からの分に昼の長さを足した値)。
- `Frame` に `public var timeMark: TimeMark` と `public var timeTint: TimeTint`(`FrameBuilder` が `TimeOfDay` で作る。コンテンツの `timeTint` が無ければ `defaultDef`)。
- `TileView` に `public var brightness: Int?`(‰。地形の層に掛ける明るさ。nil は「時刻を掛けない」= 光る物と未踏)。`MapProjection` が次の規則で決める(§6.7.2):
  - 昼: 視界の中は `timeTint.brightness`、既知で視界の外は今の `remembered`(420‰)に `timeTint.brightness / 1000` を掛けた値。
  - 夜: 灯りの円(燃えている火床の灯りの半径。炉の灯りを含む。`Hearths.lightRadius` と、今の視界の計算 `Vision.swift` と同じ距離の測り方)の中は `timeTint.brightness`、円の縁の 1 マス(距離 = 半径)は 500‰、円の外の既知の地形は `timeTint.outside`、未踏は nil(黒)。
  - 光る物(`glow`)のマスは nil(時刻を掛けない)。
- 夜に灯りの円の外にある人・敵・置いた物は、`Frame` の `actors`・`placements` に**載せない**(今、夜の視界の外のものを載せているなら直す。昼は今のまま)。人と置いた物の字の色は、時刻で変えない(TEST-O23 の (6)。色の計算に `timeTint` を使わない)。
- 保存には何も足さない(時計から毎回作る)。

## 3. テスト(`Tests/RFPresentTests/TimeOfDayTests.swift` を新規。TEST-O23)
1. 昼の 64 段の隣どうしで、`brightness` と `strength` の差がどちらも 30‰ 以下(公開の層の表で)。
2. 純関数: 同じ分なら同じ `TimeTint`。`SaveCodec` で保存した JSON に `timeTint`・`brightness` の文字が無い。
3. 昼と夜の全部の段で、`mark` と、色味を作った区間の始まりの点の `mark` が一致する。
4. 夜: 火床 1 つ(半径 r)の世界で、円の中の地形が `brightness`、距離 r のマスが 500、円の外の既知のマスが `outside`。円の外にいる人・置いた物が `Frame` に無い。火床の段を下げると、同じフレームで円が縮む。`glow` のマスは円の外でも `brightness` が nil。
5. 手がかりの色: 公開の層の地形の色(`Palette` の草・森・水・岩・更地)を、全部の目印の点の色味に通しても、色相のずれが 20° 以内で、色相の並びの順が変わらない(色相の計算は整数でも浮動小数でもよい。テストの中だけ)。
6. 昼の人・置いた物の字の色が、どの刻みでも同じ。
7. `timeTint` の無いコンテンツで、昼は 1000‰・夜の円の中は 750‰ で、今の見え方と同じ。
8. 検証: 点が昇順でない・`strength` 400・予約の赤の色味、がそれぞれ error。公開の層は error 0。

## 4. 確かめのコマンド
```
~/.local/bin/rf-note-test . --filter 'RFPresentTests|RFContentTests'
~/.local/bin/rf-note-test .                        # 全体(公開の層)。終了コード 0
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- note に ssh できなければ予備(hub): `~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter <テスト>`。hub では全体を回さない。
- 土台を替えたら `rf-note-test -c …` で note の .build を消してから回す。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFContent/`(`Schema/TimeTint.swift` 新規・`ContentDB.swift`・`ContentLoader.swift` の `timeTint` のキー・`ContentValidator.swift`)、`ReForgeCore/Sources/RFPresent/`(`TimeOfDay.swift` 新規・`Frame.swift`・`FrameBuilder.swift`・`MapProjection.swift`・`Palette.swift` の予約の赤の判定)、`ReForgeCore/Tests/RFPresentTests/`・`RFContentTests/`、`content/public/world.json`(`timeTint` だけ)。
- 触らない: アプリ(`ReForge/`。W-19)・`content/private`・保存の形・`Vision.swift` の視界の規則そのもの(読むだけ)。

## 6. 約束(F §4)
- 公開リポジトリに物語の語を書かない。
- 本体の色の計算に浮動小数を使わない(整数の ‰)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない(帯の言葉は W-19 で `ui.time.*` の文言の表から引く)。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(F §4。統合担当がマージの前に、古い形の非公開の層で回す。非公開の層が `timeTint` を持たない・持つの両方で)。
- 枝の名前・先頭のハッシュ・4 の結果(件数)・予約の赤の判定をどこから取ったか・夜の `actors` を直したかどうか。
