# W-22 解禁の要る行為を、解禁まで出さず受けない(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `main` の先頭(本体だけ。アプリは変えない)。小さな単位。
なぜ: 研究・スキル・効果で解く行為(`unlocks` に `{ "interaction": … }` と書かれた行為)が、解く前から足元カードに出て、押せば受け付けられる。`ContentDB.gatedUnlocks`(解禁の要る物の集まり)は定義されているが、どこからも読まれていない。

## 本体(Linux で確かめる)
- 行為が「使える」の規則を 1 か所に置く: `Interactions.isUnlocked(_ id: InteractionID, world: WorldState, gated: Set<UnlockTarget>) -> Bool` = `!gated.contains(.interaction(id)) || world.research.unlocked.interactions.contains(id)`。
- `gatedUnlocks` は毎回組み立てない(全部の研究とスキルをなめる)。`ContentDB` を読み込んだ時に 1 回だけ作って持つ(例: `ContentDB` の読み込みの後で計算した値を、`Simulation` と `FrameBuilder` が初期化で受け取って持つ)。
- 受け付け: `Interactions.start`(と、行為を始める全部の口。続けて採る・配属の採集 `startAssignedGathering` を含む)の最初の確かめに足す。解禁前なら `Rejection("reason.explore.locked")`。文の ID を 5 言語で足す(ja「まだやり方が分からない」程度の中立の文)。
- 足元カード: `FrameBuilder.footCard` の行為の選び出しで、解禁前の行為は出さない(`ui.isOpen` と同じ所で弾く)。PT-B8 の暗い場面の行為(足元カードから選ぶ)も、これに従う。
- 始まりの解禁(`start.unlocks`)は今どおり、解禁済み(`gatedUnlocks` から除かれている)。
- 保存の形は変えない(`research.unlocked.interactions` は既にある)。古い保存で、解禁前に使っていた行為は、解禁されるまで出なくなる(それで正しい)。

## テスト(Linux。公開の層)
- 公開の層の試験の内容に、試験の研究 1 つと、それで解く試験の行為 1 つ(始まりの場所が対象)を足す。
- 解禁前: 足元カードにその行為が無い・命令を送ると `reason.explore.locked` で断られる・配属の採集でも始まらない。
- 研究を済ませる(または効果 `unlock` を当てる)と、同じマスの足元カードに出て、受け付けられる。
- 始まりの解禁に入っている行為は、最初から出る。解禁の要らない行為は今どおり。
- 既存のテストが全部通る(公開の層の行為で `unlocks` に入っている物があれば、テストの世界で解禁してから使う形に直す)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す(非公開の層は、解禁の要る行為がデータの `when` でも隠されている。どちらでも通ること)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 凍った見本 `save-v1-dev-*.json` は作り直さない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
