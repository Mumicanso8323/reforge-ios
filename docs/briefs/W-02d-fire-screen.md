# 説明書 W-02d: 火の画面(帯の火のゲージ・寝る見込みの 1 行・申し出の「頼む」)

作業の単位: 序盤 W-02d(設計: reforge-plan `docs/plans/2026-10-02-opening-and-industry-depth.md` v0.7 以降の W-02d・UI-04・UI-08・UI-09・BEAT-19・TEST-O11・RISK-O2・§3.4)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: W-02a(`HearthRule`)・W-11(`Simulation.forecastSleep`)・PT-B1(`HearthRule.outlook`)・W-04(`Assignment.tendHearth`)・W-26(番が山を満たす)。**すべて integration-d に入っている**。土台: integration-d の先頭。
2 つに分けて渡せる: **A 本体**(hub で全部確かめられる)→ **B アプリ**(macOS の CI で確かめる)。1 回で渡すなら A、B の順に作る。

## 0. すでにあるもの(作り直さない)と、足りないもの
ある: `HearthRule.level`(5 段)・`HearthRule.outlook` / `outlookAfterOneMore` / `outlookWithPile`(4 段 `FireOutlook`)、`FootCard.fire`(足元カードの「今 → 1 本くべると」)、`ClockView.fireOutlook`(日没の帯に「火: …」を 1 つ)、`Simulation.forecastSleep`(寝た結果を写しで回す)とその一致の試験、番の配属 `.crew(.assign(person:, assignment: .tendHearth(placement:)))` と `CrewWork.refusal`(手が先)。
足りない:
1. 帯の**火のゲージ**(UI-04。言葉 5 段)が Frame にも画面にも無い(`UIElements.bandFire` の ID だけある)。
2. **見込みの式が 2 つある**: 足元カードの `fire.now` は `outlook`(番の薪を見ない)、日没の帯は `outlookWithPile`(山を見る)で、番がいると食い違う。さらに実際の歩み(`Hearths.fillPile`)は番がいれば拠点の蓄えの薪も山へ運ぶが、見込みは蓄えを見ない。
3. **寝るボタンの見込みの 1 行**が、`forecastSleep` の結果ではなく `outlookWithPile` から作られている(W-11 の約束「別の式で見積もらない」)。炉が冷えるかの見込みは無い。
4. **申し出**(仲間が自分から番を申し出て、プレイヤーが「頼む」を押す)の型・出し方が無い。今は仲間のタブの配属でしか番を頼めず、そのタブの割り当ての選択肢にも番が無い。

## 1. 目的
火の状態を、最初の火が点いたときから帯の言葉 5 段で見せる。日没には、押す前に結果が分かる 1 行(寝るとどうなるか)を寝るボタンの上に出す。番がいない夜には、番を申し出る人が帯に出て、「頼む」を 1 回押すだけで番に付く(自動では付かない)。どれも**押したことは必ず受け付けられる**ものだけを見せ、確認も理由の文も出さない。
言葉・色・印は状態の表示で、操作の説明ではない(チュートリアルにしない)。

## 2. A 本体(RFRules・RFPresent・RFContent)

### 2.1 見込みの式を 1 本にする(INV-D1)
```swift
// RFRules/Hearth.swift
public struct FireGauge: Equatable, Sendable {
    public var level: HearthLevel      // 5 段(消えている…盛ん)。HearthRule.level と同じ
    public var outlook: FireOutlook    // 4 段。尽きる時刻。日没・夜の間の見込み
}
extension HearthRule {
    /// ゲージと見込みの唯一の入口。level と outlook を同じ状態・同じ simulate から出す。
    public static func gauge(_ s: HearthState, _ def: HearthDef, now: GameTime, clock: ClockDef,
                             structuresInLight: Int, tended: Bool, stock: Int,
                             modifiers: HearthModifiers = HearthModifiers()) -> FireGauge
}
```
- `stock` は拠点の蓄えにある薪の山の品(`def.pileItem`)の数。**番がいるとき(`tended`)だけ**、山の本数 = `s.pile + stock` として `outlookWithPile` と同じ式で数える(`Hearths.fillPile` が山の空いたときに蓄えから運ぶのと同じ結果になる)。番がいなければ山も蓄えも見ない。
- `FrameBuilder` に `func fireGauge(of placement: Placement, _ w: WorldState) -> FireGauge?` を 1 つ置き、**次の 3 つはすべてここから取る**: `ClockView.fireOutlook`(今の `duskFireOutlook`)・`FootCard.fire.now`(`afterOneMore` は `outlookAfterOneMore` に同じ `tended`・`stock` を渡す)・新しい Frame のゲージ。`DayWrap` の火の候補も同じ値を使う。式を 2 つ以上書かない。
- 既存の `outlook` / `outlookAfterOneMore` / `outlookWithPile` の引数は変えない(`stock` を引数に足すか、`s.pile` に足した状態を渡すかは任せる。既存の `FireOutlookTests` は全部そのまま通す)。

### 2.2 ゲージ(UI-04)
```swift
// Frame に
public var fireGauge: FireGaugeView?
public struct FireGaugeView: Equatable, Sendable {
    public var level: HearthLevel
    public var outlook: FireOutlook
}
```
- `nil` の条件: 建て終えた火床の建造物(`Hearths.structureHearths` の最初。拠点の焚き火)が無い間。**最初の火が点く前は nil**(出さない物は見せない。Z2)。消えていれば `level == .out` で出す(火を一度でも持ったとき)。
- 画面へ出すかの門は、画面の側で `UIElements.bandFire` が開いているか(2.5)で決める。Frame は門を見ない(今の他の要素と同じ)。
- 言葉(固定の文言。日本語)は画面の側: `.out` 消えている・`.smoldering` くすぶっている・`.flickering` ちらついている・`.burning` 燃えている・`.roaring` 盛んに燃えている。**本体の `Sources` に日本語を書かない**。

### 2.3 寝る見込みの 1 行(W-11・TEST-O11)
```swift
// RFPresent
public struct SleepForecast: Equatable, Sendable {
    public enum FireAtDawn: Equatable, Sendable { case holds, dies }
    public enum FurnaceAtDawn: Equatable, Sendable { case stays, cools }
    /// 今点いている焚き火が、寝た夜明けにまだ点いているか。点いていなければ nil。
    public var fire: FireAtDawn?
    /// 今熱い炉(1100℃ 以上など `FurnaceHeat.isHot`)がある。夜明けに全部熱いままなら stays、1 つでも冷えれば cools。熱い炉が無ければ nil。
    public var furnace: FurnaceAtDawn?
    public var isEmpty: Bool { fire == nil && furnace == nil }
}
extension GameHost {
    /// 日没・夜作業の間だけ。写しに `.time(.sleep)` を当てた結果(Simulation.forecastSleep)から作る。昼は nil。
    public func sleepForecast() -> SleepForecast?
}
```
- 結果は `forecastSleep` の写しの世界 `after` から読む(別の式で見積もらない)。`fire`: 今点いている焚き火の火床について、`after` で `lit && fuel > 0` か。`furnace`: 今熱い炉それぞれについて `after` で `FurnaceHeat.isHot` か。
- **Frame には入れない**(寝る 1 夜ぶんを回すので、毎フレームは重い)。画面は `store.host` の呼び出しで、日没の間だけ、世界の版が変わったときに引く(拠点のタブの `host.base()` と同じ作法。`.task(id: store.revision)`)。
- 世界・乱数・保存を進めない(`forecastSleep` は写しで回す)。

### 2.4 申し出(BEAT-19・UI-09)
```swift
// RFContent/Schema/CrewWork.swift の CrewWorkDef に任意の欄を足す(JSON も同じキー。無ければ従来どおり)
public var tendOffer: TendOfferDef?
public struct TendOfferDef: Codable, Equatable, Sendable {
    /// 申し出る人の順(先頭から、出せる人が 1 人出る)。無ければ仲間の並びの順。
    public var order: [PersonID]?
    /// 人ごとの申し出の一言(文字列表の鍵)。無い人は一言なし。物語の文はデータの側。
    public var lines: [PersonID: TextID]?
}

// RFPresent / Frame に
public var offers: [PendingOffer]
public struct PendingOffer: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case tendFire }
    public var kind: Kind
    public var person: PersonID
    public var name: String          // 認識の層を通した人の名前
    public var line: String?         // tendOffer.lines の一言(文字列表から)
    public var command: Command      // 押すと送る。.crew(.assign(person:, assignment: .tendHearth(placement: 焚き火)))
}
```
- **状態を足さない**(保存の形は変えない)。毎回、世界から導く。申し出は**ダイアログではなく**、日没の帯に出る 1 行の部品(Frame の値)。
- 出す条件(全部成り立つとき、1 人だけ・`kind: .tendFire`):
  1. 時刻が日没か夜作業(`clock.phase != .day`)。
  2. 拠点の焚き火が建て終わっていて点いている(`HearthRule.level != .out`)。
  3. その火に番がいない(`Hearths.isTended` が false)。
  4. 申し出る人: 仲間(操作する人以外)で、生きていて地図にいて、`CrewWork.refusal(.tendHearth(placement: 火), for: 人, …) == nil`(手が先)で、すでにその火の番ではない人。`tendOffer.order`(無ければ仲間の並び)の先頭から最初の 1 人。
- **押せば必ず受かる**(INV-D2): `PendingOffer.command` を今の世界に当てて `rejection == nil` になる人・条件だけを出す。出す条件を `CrewSystem.assign` の受け付けと同じ判定で作る(受け付けの前提 = 仲間であること・地図にいること・`CrewWork.refusal` が nil)。
- 押した後は番が付くので、申し出は次のフレームで消える。押さずに寝れば、夜明けで(昼になって)消える。再び出るかは毎晩の条件のまま。
- 申し出が出る・出ない、は `UIElements` の門に結ばない(申し出そのものが、仲間のタブを初めて開く入口。UI-09 は「初めて誰かに頼んだ」で導出されるので変えない)。

### 2.5 テスト(A)
RFRulesTests に `HearthGaugeTests`、RFPresentTests に `FireScreenTests`(新規)。火床の組み立ては `RFPresentTests/ContinuePresentTests.swift` の `withCampfire`、炉は `RFProductionTests/FurnaceHeatTests.swift` の組み立てを写す(中立の ID)。
1. **式は 1 本**(INV-D1): 燃料・山・蓄え・番の有無・段・時刻を振った表(各 100 以上)で、`FrameBuilder` が出す `ClockView.fireOutlook`(日没のとき)・`FootCard.fire.now`・`Frame.fireGauge.outlook`・`DayWrap` の火の候補が、常に同じ `FireOutlook` から作られている。`FireGauge.level == HearthRule.level`。
2. **見込み = 実際**(TEST-O11): seed と火床・炉の状態を振った 1000 の夜(重ければ既定 300 にして環境変数 `REFORGE_O11_NIGHTS` で 1000 に上げ、かかった時間を報告に書く)で、日没(番がいる・いない・蓄えの薪が有る・無い)の世界について、`SleepForecast.fire`・`furnace` と、実際に `.time(.sleep)` を当てた夜明けの世界が**全部一致**する。さらに、番がいる・いないを問わず `Frame.fireGauge.outlook == .throughNight` ⇔ `SleepForecast.fire == .holds`(点いている火について)。**境目(燃料がちょうど夜明けに尽きる)は、実際の動きに合わせる**: 食い違ったら `outlook` の境目を直し、既存の `FireOutlookTests` が落ちるなら直さず報告する。
3. **世界を変えない**: ゲージ・申し出・`sleepForecast` を呼ぶ前後で世界が等しい。乱数の流れも進まない(呼んだ後の次の一歩が、呼ばなかった世界と一致)。
4. **ゲージの出し入れ**: 焚き火が無い世界・建造中の世界では `fireGauge == nil`。点けた同じ Frame で `level` が `.smoldering` 以上。燃料が尽きて消えれば `.out`。
5. **申し出**: (a) 昼は 0 個。(b) 日没で、点いていて番がいなくて、手が先を満たす仲間がいれば 1 個。`order` の先頭の人が出る。手が先を満たさない人・番に付いている人・地図にいない人・亡くなった人は出ない。(c) 火が消えている・番がいる日没は 0 個。(d) 出た申し出の `command` を当てると、必ず `rejection == nil` で、次の Frame で申し出が 0 個になり、`Hearths.isTended` が true。(e) 1000 の夜の状態を振って、出たすべての申し出が (d) を満たす(INV-D2。**「見せて断る」を作らない**)。(f) 申し出を押さずに寝て夜明けになると、世界は申し出が無かった世界と同じ(自動では付かない)。
6. **古い内容**: `tendOffer` も火床も無いコンテンツで、`fireGauge == nil`・`offers == []`・既存の Frame の試験が全部通る。
7. **保存**: 保存の JSON に `offers`・`fireGauge`・`sleepForecast` の文字が出ない(`SaveCodec` で保存した世界)。凍らせた見本は作り直さない。
8. **文**: `FrameText.allStrings(frame)` に、ゲージ・申し出の理由を説明する文が入らない(申し出の一言は `tendOffer.lines` の文字列表の文だけ)。`ReForgeCore/Sources` に日本語のリテラルを足していない(`rg '[ぁ-んァ-ヶ一-龠]' ReForgeCore/Sources` の増えた行が 0。コメントを除く)。

## 3. B アプリ(`ReForge/Sources/Game/`。macOS の CI で確かめる。hub では型検査できない)

### 3.1 帯の火のゲージ(`StatusBandView.swift`)
- `store.fireGauge`(Frame から写す。`dayWrap` を写している 2 か所と同じ作法)が非 nil で、`store.ui.isOpen(UIElements.bandFire)` のとき、帯の項目の並び(日・昼の残り・数値の項目)の流れに 1 項目足す: `火` の見出し(`InkColor.textDim`)+ 5 段の言葉 + 色。言葉は固定の文言(2.2)。
- 色(状態は色で): 見込みが `.throughNight` → `InkColor.text`、`.beforeDawn`・`.midnight` → `InkColor.notice`、`.untilEvening` と `level == .out` → `InkColor.alert`。予約の赤 `InkColor.reserved` は使わない。
- 押せる物ではない(ボタンにしない)。`accessibilityIdentifier("fireGauge")`、値は `accessibilityValue` に段の言葉。
- 日没の帯の「火: …」(`duskFireOutlook`)は**消す**(寝る見込みの 1 行 3.2 が同じことを正確に言うので、二重にしない)。足元カードの「今 → 1 本くべると」は残す(`fire.now` は 2.1 で同じ式になる)。

### 3.2 寝るボタンの見込みの 1 行(`MapActionBand.swift`)
- 日没・夜作業の帯(`store.clock.bandActions` が空でない枝)の、ボタン群の**上**に 1 行。`.task(id: store.revision)` で `await store.host.sleepForecast()` を引く(世界の版が変わるたびに引き直し、日没でなくなれば nil)。
- 言葉(固定): `fire == .holds` 「火は夜明けまで持つ」・`.dies` 「火は夜明けまでに消える」・`furnace == .stays` 「炉は朝まで熱い」・`.cools` 「炉は朝までに冷える」。`isEmpty` なら行ごと出さない。色: `.dies`・`.cools` は `InkColor.notice`、ほかは `InkColor.textDim`。
- 「寝る」「夜作業をする」のボタンは今のまま**常に押せる**(確認なし・見込みで押せなくしない)。`accessibilityIdentifier("sleepForecast")`。

### 3.3 申し出の「頼む」(同じ帯)
- 見込みの行の下・ボタン群の上に、`store.offers` の各 1 行: 人の名前 + 一言(あれば)+ 小さな「頼む」のボタン(`.buttonStyle(.ink(.secondary))`、押す大きさは他のボタンと同じ最小高さ)。押したら `store.send(offer.command)` だけ(確認なし・結果の文なし)。受け付けられた応えは、申し出の行が消えることと、ゲージの帯が変わることで見える。`accessibilityIdentifier("offer-tendFire")`。
- ダイアログ・シート・アラートにしない。帯が閉じている(決断の帯・日の途中)ときは出ない(Frame が昼に空を返す)。
- `GameStore` に `private(set) var offers: [PendingOffer]` と `fireGauge` を足し、Frame の更新の 2 か所(初期化と更新)で写す。差分があるときだけ代入する(`dayWrap` と同じ)。

### 3.4 静的な検査・UI の試験
- `tools/check-no-reason-text.py` の `FILES` に、足した画面のファイル(帯の部品を別ファイルにしたら)を足す。`python3 tools/gen-xcstrings.py` で `Localizable.xcstrings` を作り直す(`--check` が通る)。`check-app-switches.py`・`check-app-names.py`。
- `ReForgeUITests/` に 1 本: 起動 → 最初の火を点ける → `fireGauge` が出る。日没まで進める(または試験用の世界の差し替え)→ `sleepForecast` と `offer-tendFire` が出る → 「頼む」を押す → `offer-tendFire` が消え、「寝る」は押せたまま。火が点く前は `fireGauge` が存在しない。

## 4. 確かめのコマンド(テストは hub だけ。絞って回す)
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter HearthGaugeTests --filter FireScreenTests --filter FireOutlookTests --filter ContinuePresentTests --filter DayWrapTests --filter OpeningDisclosureTests
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-no-reason-text.py
python3 tools/gen-xcstrings.py --check
python3 tools/check-public-spoilers.py
```
- 全体は回さない。B のビルドは macOS の CI。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFRules/Hearth.swift`、`ReForgeCore/Sources/RFContent/Schema/CrewWork.swift`(`tendOffer`)・`ContentValidator.swift`(`order` の人・`lines` の鍵が存在するか)、`ReForgeCore/Sources/RFPresent/`(`Frame.swift`・`FrameBuilder.swift`・`DayWrap.swift` の火の候補・`GameHost.swift`・新規 `SleepForecast.swift`・`Offers.swift`)、テスト(`RFRulesTests`・`RFPresentTests`・`RFContentTests`)、B: `ReForge/Sources/Game/`(`StatusBandView.swift`・`MapActionBand.swift`・`GameStore.swift`・`FireOutlookLine.swift` は触らない)、`ReForge/Resources/Localizable.xcstrings`(`gen-xcstrings.py` で)、`ReForgeUITests/`、`tools/check-no-reason-text.py`。
- 触らない: `RFWorld` の保存の型・`RFCrew`(配属の受け付けの規則そのもの。読むだけ)・`Simulation.forecastSleep`(読むだけ)・`content/public/*.json`(試験の中で重ねる)・`content/private`・物語の文。

## 6. 約束
- 公開リポジトリに物語の語を書かない。申し出る人の名前・一言は**データ**(`tendOffer`)で、試験は中立の ID・文(`person.test_*`・`text.test.*`)。
- 見せた物は押せば必ず受かる。押せない物はボタンにしない。確認のダイアログ・説明文・チュートリアル・理由の文を出さない。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない。整数だけで計算する。
- 出す部品は使えるようになってから 1 つずつ(ゲージは最初の火の後・申し出は日没に条件が揃ったとき)。
- 保存の形を変えない。物語の本文を変えない。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く。
- 枝の名前・先頭のハッシュ・4 の結果(件数)・TEST-O11 の夜の数と所要時間・2.5 の 2 で境目を直したか・`ClockView.fireOutlook` / `FootCard.fire.now` / `DayWrap` が同じ入口になったか。
- データの側で統合担当が置く物(`tendOffer` の `order` と `lines`・ゲージの門 `band.fire` を `ui-gates` に置くか)を鍵だけで書く。仲間のタブの割り当ての選択肢に番が無いこと(申し出以外の入口)は、この単位では足していない。
