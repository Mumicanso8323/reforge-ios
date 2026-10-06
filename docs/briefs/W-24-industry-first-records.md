# W-24 工業の「初めて」の記録の札を 2 つ足す(+ 急がない: 暦の見込みの 1 行)(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `integration-c` の先頭。小さな単位。
もと: game-designer の中盤の山の置き方 v0.2。今の初めての記録の札は `tag.invention.first_smelt`(最初の製錬の全体)だけで、「高温の炉を初めて点けた」と「電気を初めて出した」を区別できない。データの側(出来事の `when`・引き金)は U14。

## 決めた名前
| 札 | いつ付く | 記録 |
|---|---|---|
| `tag.invention.furnace_hot`(毎回)・`tag.invention.first_hot_furnace`(初めての 1 回だけ) | 炉(`FurnaceHeatDef` を持つ置いた物)が、予熱から `workTemp` に初めて届いたステップ(冷えて予熱し直して届いた時も `furnace_hot` は付く) | `ctx.record(.heated, .module(kind, id) / .structure(kind, id), place:)`。新しい行い `ActKind.heated` |
| `tag.invention.powered`(毎回)・`tag.invention.first_power`(初めての 1 回だけ) | 「電気を出す」置いた物が、建ち終わって働き始めたステップ。電気を出す物は、内容の定義の `provides["power"]` が 1 以上の物(モジュールは動いている間、建造物は建ち終わって `whenLit` の条件が効いている間)。止まって再び働き始めた時も `powered` は付く | `ctx.record(.powered, …, place:)`。新しい行い `ActKind.powered` |
- 「初めて」は、ledger にまだその毎回の札(`furnace_hot` / `powered`)の記録が無かった時(`first_smelt` と同じ決め方。`RFInvention/Trial.swift` の `firstSmelt` を手本に)。
- 名前は `InventionTags`(RFInvention/Vocabulary.swift)に足す(内容のデータがすでにこの名前で指している。名前を変えると黙って起きなくなるので、この表の綴りのまま)。
- 条件からは今の形で引ける: `{"ledger": {"query": {"tag": "tag.invention.first_power"}, "atLeast": 1}}`、引き金は `{"on": ["heated"], "when": {"firstTime": {"query": {"act": "heated"}}}}`。出来事の `on` に新しい行いの名前が使えるようにする(今の `ActKind` の文字列の形に合わせる)。
- 保存の形は変えない(記録は今の ledger の形。新しい行いの名前が増えるだけ)。

## 急がない: 暦の見込みの 1 行
- 帯の見込みの 1 行の種類(`DayWrap` の候補の型)に `calendarOutlook(daysLeft: Int)` を足す。出すのは、内容の事実(季節の答えを知った事実。ID は内容の定義 `clock.calendarFact: FactID?` で与える)を知った後だけ。`daysLeft` は次の季節の替わりまでの日数(季節の定義から計算)。文の ID `ui.daywrap.calendar_days_left`(5 言語。数は ICU の plural)。
- 事実が無い・季節の定義が無い内容では出さない。

## テスト(Linux。公開の層の試験の内容)
- 試験の炉を予熱して `workTemp` に届かせると、`heated` の記録に `furnace_hot` と `first_hot_furnace` が付く。冷やして予熱し直すと、2 回目は `furnace_hot` だけ。
- `provides["power"]` を持つ試験のモジュールを動かすと `powered` と `first_power`。止めて動かすと 2 回目は `powered` だけ。`power` を持たない物では付かない。
- 条件 `firstTime` と `ledger` で引ける。出来事の `on: ["heated"]` で引き金になる。
- 暦: 事実を知る前は候補に無い・知った後は `daysLeft` が季節の定義どおり。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`(`ActKind`・見込みの型に case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 凍った見本 `save-v1-dev-*.json` は作り直さない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
