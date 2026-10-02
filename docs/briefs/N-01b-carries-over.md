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

## まだ残る同じ系の言葉(この単位では替えない。リーダーが決める)
公開のコードに `rewind` の系の言葉が、ほかにも 28 のファイル・81 か所ある(例: 走りの状態の `rewinds` の数・保存の要約の `rewinds`・失敗からの戻りの型の名前・`content/public/run/rewind.json`)。凍らせた見本にも `rewinds` のキーがある。替えるなら、同じ形(LegacyNames の対応表・起動の書き直し・書き換えの対応表)で N-01c にする。今の公開の検査(`check-public-spoilers.py`)では止まっていない。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す(U14 の替えの前と後の両方で読める)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- `git grep persistsAcrossRewind` が、LegacyNames の対応表と、そのテストと、凍らせた見本だけになる。

## コミット
メッセージは中立に(古い名前をメッセージに書かない。「記憶の持ち越しの欄の名前を替える」)。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
