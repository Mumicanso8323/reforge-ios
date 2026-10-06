# PT-B3 押したときの反応の表と、最小の音と触覚(Codex への説明書)

書いた人: architect(統合担当。game-designer の下書きから型を決めた)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(PT-B1 の後。手作業の進み `progressPermille` を使う)。
なぜ: 入力には 0.1 秒以内に反応を返す。手作業のボタンは今、押している間に色が変わるだけで、進みも 1 単位ができたときの手応えも無い。手触りは後から足すと高くつくので、最小の音と触覚を今入れる。

## 1. 本体: `Frame.pulses`(RFPresent。Linux で確かめる)
- 1 回の組み立ての間に起きた、手応えを返すべきこと。`FrameBuilder.build(_:revision:previous:report:)` が、渡された `StepReport` の出来事(と前のフレームとの差)から作る。前のフレームから後に起きた分だけを入れ、次のフレームには残さない。
  ```swift
  public enum Pulse: Equatable, Sendable {
      case unitDone(name: String, count: Int)   // 手作業・採集の 1 単位(認識の層を通した名前)
      case placed                                // 置いた・建て始めた
      case finished(name: String)                // 建て終わった・作り終わった
      case firstTime(name: String)               // 初めての物・初めて動いたライン
      case rejected(reason: String)              // 断られた(理由の文)
      case fed                                   // くべた
      case fire(FirePulse)                       // 火が点いた・弱まった・消えた
      case nightBegan
      case decisionShown                         // 決断の帯が出た
  }
  public enum FirePulse: String, Equatable, Sendable { case lit, weakened, out }
  extension Frame { public var pulses: [Pulse] }
  ```
- 世界は変えない(来歴と出来事から作るだけ)。

## 2. アプリ: `PulsePlayer`(音・触覚・浮かぶ文字)
| できごと | 見た目 | 文字 | 音 | 触覚 |
|---|---|---|---|---|
| ボタンを押した | 押した瞬間に色が変わる(今のまま) | — | `ui_press` | 選択(軽) |
| 手作業の進み | 足元カードのボタンの下にバー(`progressPermille`) | — | 火起こしだけ `ui_rub`(ほかは無音) | 火起こしだけ `hapRub`(軽い連続) |
| 手作業の 1 単位(`unitDone`) | バーが一瞬明るく光って空に戻る | 「+1 〈物〉」が 0.5 秒浮かぶ(同時に 5 個まで) | `ui_unit` | 選択(軽) |
| 置いた(`placed`) | 置いた所が 1 度ふくらむ | — | `ui_place` | 選択(軽) |
| できた(`finished`) | 置いた物の字が 1 度光る | 「〈物〉ができた」を帯に 2.5 秒 | `ui_done` | 成功(中) |
| 断られた(`rejected`) | ボタンが左右に 1 度ゆれる | 理由の 1 行(今のまま) | `ui_reject` | 警告(弱) |
| くべた(`fed`) | 火の字が 2 秒ふくらむ | — | `ui_feed_1`〜`3`(順に) | 選択(軽) |
| 火が点いた(`fire(.lit)`) | 地図が灯る(今のまま) | — | `ui_ignite` | `hapIgnite`(中) |
| 火が弱まった・消えた | 火の字が暗くなる | 帯に 1 行 | `ui_fire_down` | `hapFireDown`(弱) |
| 日没(`nightBegan`) | 帯の色が夜に変わる | 夜の締め(PT-B2) | `ui_night`(低い 1 秒) | — |
| 初めて(`firstTime`) | 物の字が 2 度光る | 「初めての〈物〉」を帯に 2.5 秒 | `ui_done` を 1 段強く | 成功(中) |
| 決断の帯(`decisionShown`) | 帯が下から出る | — | — | `hapDecision`(中) |

- **押した瞬間の反応(色・`ui_press`・選択の触覚)は、本体を待たずに画面の中で返す**(ボタンの押下で直接)。入力から最初の画面の変化まで 100ms 以内。
- 文字は固定の文言 + 物の名前だけ。
- 音: 上の 12 個の名前(`ui_press`・`ui_rub`・`ui_unit`・`ui_place`・`ui_done`・`ui_reject`・`ui_feed_1`・`ui_feed_2`・`ui_feed_3`・`ui_ignite`・`ui_fire_down`・`ui_night`)。曲は入れない。
  - **音の素材は仮のものを生成する**: `tools/gen-ui-sounds.py`(Python の標準のライブラリだけ。正弦波・雑音・包絡線で短い音を作り、`ReForge/Resources/Sounds/<名前>.wav` に書く。モノラル・44.1kHz・16bit・各 1 秒以内)を足し、生成した wav をコミットする。本物の音は後で差し替える(名前はそのまま)。
  - 鳴らし方: `AVAudioSession` のカテゴリは `.ambient`(ほかのアプリの音楽を止めない・消音スイッチで消える)。短い音は `AVAudioPlayer` を前もって読み込んで鳴らす(初回の遅れを避ける)。
- 触覚: 3 種(選択 = `UISelectionFeedbackGenerator`、成功・警告 = `UINotificationFeedbackGenerator`)と、名前つきの 4 つ(`hapRub`・`hapIgnite`・`hapFireDown`・`hapDecision`。`UIImpactFeedbackGenerator` の強さで作る)。触覚は音と同じフレームで。0.3 秒より詰めて打たない。序と、文だけの場面には付けない。触覚だけで伝える情報を作らない。
- 設定: 「効果音」の音量(0〜100)・「触覚」の入切(`UserDefaults`。保存に入れない)。端末の「視差効果を減らす(動きを減らす)」が入っているときは、浮かぶ文字とゆれを出さず、色の変化だけにする。

## 3. 不変条件
- INV-B3-1 押した瞬間の反応は、本体の応答を待たない。
- INV-B3-2 `pulses` は来歴と出来事から作る。音・触覚を切っても、世界は同じ。
- INV-B3-3 触覚だけ・音だけで伝える情報が無い(必ず見た目か文字と組)。

## 4. テスト
| ID | 中身 |
|---|---|
| TEST-B3-1 | (Linux)手作業の 1 単位ができたステップで `pulses` に `unitDone` が 1 つだけ入る。次のフレームには残らない |
| TEST-B3-2 | (Linux)断られた命令で `rejected` が理由つきで入る |
| TEST-B3-3 | (Linux)火が点いた・消えたで `fire(.lit)`・`fire(.out)` が入る |
| TEST-B3-4 | (アプリ)「動きを減らす」の入で、浮かぶ文字を作らない |
| TEST-B3-5 | (アプリ)触覚の切で、触覚の呼び出しが 0 回(差し替えた記録係で数える) |
| TEST-B3-6 | (アプリ)12 個の音の名前が全部、束の中にある |

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。macOS の CI でアプリのビルドと単体テスト。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 実機の確かめ(消音スイッチ・ほかのアプリの音楽が止まらない・押してから 100ms)は、PT の前にリーダー・使い魔と、協力してくれる人が SideStore の版でやる(オーナーは未完成の版を遊ぶテストに入らない。2026-10-02 の方針)(この作業の受け入れには入れない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
