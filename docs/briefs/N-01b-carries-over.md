# N-01b 記憶の「持ち越す」の名前を替える(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(N-01 の続き)。
なぜ: N-01 の後も、記憶の欄 `persistsAcrossRewind` が公開の 13 のファイル(本体・テスト・保存の見本 2・公開の層 3・D-save.md)に残っている。履歴の書き換えの前に消す名前なので、中立の名前 **`carriesOver`** に替える。非公開の層の側(人の生成器と人のデータ)は U14 が替える。

## 替える所
- 内容の定義: 記憶の種類の欄 `persistsAcrossRewind` → `carriesOver`(`RFContent` の Schema。JSON のキーも)。
- 世界の状態: 人の記憶の欄 `persistsAcrossRewind` → `carriesOver`(`RFWorld` の People。保存のキーも)。
- 使う所(`RFFailure` の記憶の持ち越し・`RFRules` の効果)・テスト・公開の層の 3 つのファイル・`docs/architecture/D-save.md` の言い方。
- `save-v1.json`(作り直してよい見本)は作り直す。**凍らせた見本 `save-v1-dev-*.json` は作り直さない・飛ばさない**(古いキーのまま。下の読み替えで読む)。

## 古い名前の読み方(N-01 と同じ口)
- `LegacyNames` の対応表に `"persistsAcrossRewind": "carriesOver"` を足す(キーとして読み替える。内容の JSON は `ContentLoader.apply` で、保存は `SaveCodec.decode` で、今の口のまま)。
- テスト: 凍らせた見本 `save-v1-dev-7ea0791.json` を読むと、記憶の `carriesOver` が true で読める / 古いキーと新しいキーが両方ある保存は新しい方を残す(N-01 の決まり) / 古い名前の無い保存はバイトも変えずに通す。

## 端末の保存を書き直す(LegacyNames を消せるようにするため)
- アプリの起動のとき、1 度だけ、保存の枠のファイル(自動・手動・節目の全部)を見て、古い名前を含むもの(`LegacyNames.mayContainLegacy` が true)だけを、読み替えて書き直す。書き直しは今の保存と同じ原子的な書き方(書いてから差し替える)。読めなかった枠には触らない。古い名前の無い枠はバイトも変えない。
- 書き直したかどうかは `UserDefaults` に版の印で残し、同じ版では 2 度目を走らせない。記録(ログ)は出さない。
- テスト(アプリ): 古いキーを持つ手動の枠と、持たない枠を置いて起動の処理を呼ぶと、前者だけが書き直され、読み直すと同じ世界になる。

## LegacyNames を消してよい日
次の 3 つがそろった後の、最初の統合の回。それより前には消さない。
1. U14 の名前替え(content の n01-rename と、この単位の非公開の側)が content の main に入った。
2. この単位の起動の書き直しを含む dev の版を出し、オーナーがその版を 1 度起動したことを、使い魔が確かめた(オーナーの端末の枠が全部書き直される)。ほかに dev を入れている人がいれば、その人も。
3. 履歴の書き換え(リーダー)が終わった。凍らせた見本の古いキーは、書き換えの対応表(`persistsAcrossRewind` → `carriesOver` を足した)で、履歴ごと新しいキーになる。書き換えの前に LegacyNames を消すと、凍らせた見本が読めずにテストが落ちる。
消すときは、LegacyNames と、その読み替えのテストと、起動の書き直しを同じコミットで消す。凍らせた見本が古い名前を持っていないことを、その回でもう一度確かめる(統合担当)。

## 巻き戻しで「何が残るか」を中立にする(リーダー 2026-10-02)
巻き戻しそのものは遊ぶ人に見える仕組みなので、`rewind` の系の名前(走りの `rewinds`・戻りの型・`run/rewind.json`)は残す。漏れは名前ではなく中身で、「特定の人の記憶や関係が巻き戻しを越えて残る」「仲間が前の周回を覚えている」と読める所が公開のコード・内容・テスト・文書に残っている。**試験の人を入れ替えても意味が同じになる形**(誰に何が残るかはデータが決め、本体は仕組みだけを持つ)に直す。
| 今 | 直し |
|---|---|
| `RewindDef.dejaVuMemory`(巻き戻した後、ノアを除く一員に付ける記憶)と、一言の文脈 `"rewind.deja_vu"` | `RewindDef.restartMemory: RestartMemoryDef?`(`kind: MemoryKindID`・`exclude: [PersonID]?`。巻き戻した後、夜明けの時点の一員のうち `exclude` に挙げた人を除く全員に付ける。誰を除くかはデータ)。文脈は `"rewind.after"`。本体のコードに「ノアを除く」を書かない |
| `RewindDef.memorableTags`(前の周回の記録のうち、仲間が覚えておく印) | `keptTags`(巻き戻しの後も、前の周回の記録の写しに残す来歴の印) |
| `RewindDef.relationPermille`(既定 1000 = 全部持ち越す) | 名前はそのまま。既定を持たない(nil は 0)。持ち越す割合はデータが書く |
| `RunState.pastLives`(前の周回で起きたことのうち覚えておくもの。説明に仲間の「前にも」の気配) | `priorRuns`(前の周回の記録の写し)。型 `PastLife` は `PriorRun` |
| コメント・テストの名前・D-save・B-data-model の「前の周回を覚えている仲間」「前にもこうなった気がする」などの言い方 | 「巻き戻しの後に、データが挙げた記憶を付ける」「前の周回の記録の写し」の形に。試験の記憶 `memory.test.deja_vu` は `memory.test.after`、一言 `line.test.deja_vu` は `line.test.after` |
- 保存のキー(`pastLives`)と内容のキー(`dejaVuMemory`・`memorableTags`)は、上の `persistsAcrossRewind` と同じく `LegacyNames` の対応表に足し(文脈の文字列 `"rewind.deja_vu"` も値として足す)、起動の書き直しでも新しい名前にする。書き換えの対応表にも足す(統合担当が足した)。
- 非公開の層: U14 が同じ名前に替える。**順番**: `relationPermille` の既定を外すと、非公開の層がその値を書いていなければ関係を持ち越さなくなる。U14 が先に、非公開の層の巻き戻しの定義に今の値(1000)をはっきり書き、その後にこの単位を入れる(統合担当が非公開の層を重ねて確かめる)。
- テスト: 公開の層の試験の人(test_a・test_b)を入れ替えた内容でも、同じテストが同じに通る(誰に残るかが本体に書かれていないことの確かめ)。

## まだ残る同じ系の言葉(リーダーの判断: 替えない)
`rewind` の系の名前(走りの `rewinds` の数・保存の要約の `rewinds`・戻りの型の名前・`content/public/run/rewind.json`)は残す。巻き戻しは遊ぶ人に見える仕組みで、名前そのものは答えを明かさないため(リーダー 2026-10-02)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す(U14 の替えの前と後の両方で読める)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- `git grep` で `persistsAcrossRewind`・`pastLives`・`dejaVu`・`deja_vu`・`memorableTags` を探すと、LegacyNames の対応表と、そのテストと、凍らせた見本だけになる。
- codex-review の問いに「巻き戻しで何が残るかから、物語の形が読み取れないか(誰に何が残るかが本体・公開の内容・テスト・文書に書かれていないか)」を入れる。

## コミット
メッセージは中立に(古い名前をメッセージに書かない。「記憶の持ち越しの欄の名前を替える」)。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
