# W-26 火の番が、拠点の蓄えから薪の山を満たす(実装の説明書)

書いた人: architect(統合担当)。土台: `integration-c` の先頭。本体だけ(RFRules・RFPresent の見込み)。アプリは変えない。
穴: 薪の山(`HearthState.pile`)に積む入口が、プレイヤーの `.stack` 以外に無い(画面にも内容にも送り手が無い)。番(`tendHearth`)が付いていても山が空で、くべる物が無いまま火が消える。

## 決め
- 番が居る火床(`Hearths.isTended`)では、燃やす歩みの**前に**、山が上限(`HearthRule.pileMax(def, modifiers:)`。薪の囲いの +4 を含む)に満たなければ、拠点の蓄え(`.base`)から、山の物(`def.pileItem`)を、足りるだけ(蓄えが少なければあるだけ)山へ移す。移した分は蓄えから減る。蓄えが無ければ何もしない。
- くべるのは今まで通り山から(`HearthRule.burn` の tended)。`burn` は純粋なまま変えない。
- 番が居ない火床には何もしない。プレイヤーの `.stack`(`HearthCommands`)はそのまま。
- 実装の場所: `Hearths.advanceStructures`(`RFRules/Hearth.swift`)の `burn` の直前。蓄えの取り方は `ctx.takeStock(n, from: .base, where:)`(`HearthCommands.take` と同じ。全部そろわなければ取らない形なので、取れる数を先に数える)。
- 出来事: 山が増えた時、`ctx.changes.mark` は `write` が行う分で足りるか確かめる。新しい `DomainEvent` は足さない。
- 見込み(`FrameBuilder` の `outlookWithPile`・`Hearths` の見込み)は、番が居る時に「山は上限まである」と見なすか、今の山のままか、実際の歩みと食い違わない方を選ぶ。食い違うなら、見込みは今の山のままにして、コメントで理由を書く。

## テスト(`RFBaseTests/HearthTests.swift` に足す)
1. 番あり・蓄えに燃料 10・山 0 → 次の歩みで山が上限まで増え、蓄えがその分減る。
2. 番あり・燃やして夜を越す(18 ゲーム時間相当を歩ませる)→ 蓄えが足りる限り火が消えない。
3. 番なし → 山も蓄えも変わらない。
4. 蓄えが空 → 山は増えず、エラー・警告も出ない。
5. 囲い(`hearth.pile` +4)が灯りの中にある時、山の上限が +4 になり、移す数も +4 される。
6. 保存して読み戻して続けても同じ。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る(note の `rf-note-test`)。
- 物語の語を書かない。

## コミット
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
