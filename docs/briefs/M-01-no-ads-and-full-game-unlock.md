# M-01 広告をなくす・本編の解放(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(N-01 が入った後)。
正本: `docs/architecture/G-extra-chapter.md` §1(DEC-G1・G2・G5、§1.2・§1.4)と `docs/architecture/D-save.md` §8。オーナーの決定(2026-10-02): 広告をやめる。最初の部分を無料にし、本編の残りを 1 回の非消耗型の購入で解放する。購入の権利はオフラインで有効。

## A. 広告をなくす(アプリ)
1. 消す: `ReForge/Sources/Monetization/AdSlot.swift`(`AdBannerContainer`・`AdSlot`・`AdProvider`・`NoopAdProvider`)、`ReForge/Sources/Screens/RemoveAdsView.swift`。
2. `ReForgeApp.swift`: `adProvider`・`adsRemoved`・`adsRemovedKey`(`UserDefaults` の印。起動時に一度だけ `removeObject` してよい)・`purchaseRemoveAds` を消す。`RootView` は `AdBannerContainer` で包まず、画面を全部の高さで置く(下の 50pt は中身へ)。土台のコメントを今に合わせる。
3. `SettingsView.swift`: 「広告」の節を「購入」の節に替える(B.4)。`removeAdsButton` の識別子は消す。
4. `GameScreen.swift` などのコメントの広告の記述、`InkCard.swift`・`InkFont.swift` の「広告を消す」「広告の注意」の例を、今の画面の言い方に直す。
5. `StoreService.swift`: `ProductID.removeAds`・`adsRemovedEntitlement()` を消す(B に置き換える)。
6. `store/iap/reforge.remove_ads/` を消し、`store/iap/reforge.fullgame/`(5 言語・`name`/`description` は空のまま)を置く。`docs/briefs/L-14-store-metadata.md` の品の ID の例を `reforge.fullgame` に直す。
7. README の「広告枠」「広告除去」の記述を、「広告は無い。最初の部分は無料で、本編の残りは 1 回の購入で解放する」に直す。
8. `python3 tools/gen-xcstrings.py` でカタログを作り直す(「広告」「広告を消す」などが消える)。
9. 画面の写真(`ReForgeUITests/ScreenSnapshotTests.swift`・`tools/collect-screens.py`)に、広告の枠を前提にした所(高さ・識別子 `adSlotBottom`)があれば外す。
- ATT(App Tracking Transparency)・広告の SDK・`NSUserTrackingUsageDescription`・SKAdNetwork は、今も入っていない。入っていないことを確かめ、入れない。

## B. 本編の解放
### B.1 本体の門(ReForgeCore。Linux で確かめる)
既定は「柵」の形(区切りの後も、その章の中で遊び続けられる。待つのはデータが決めた物だけ)。「止める」形にもデータで切り替えられる(どちらにするかはオーナーが試遊の後に決める)。
- 内容の定義: `ContentDB` に任意の `trialGate: TrialGateDef?` を足す。JSON は内容の束の上の段のキー `trialGate`(ほかの層で置き換えられる)。無ければ門は無い(今までのデータはそのまま)。
  ```swift
  public struct TrialGateDef: Codable, Equatable, Sendable {
      /// 区切りに着いたか(条件 1 つ。データが決める。例: 区切りの事実を知った)。
      public var when: Condition
      /// fence(既定): 時計・手の作業・生産・探索・戦闘は続け、holds に挙げた物だけを待たせる。
      /// freeze: 時計を進めず、命令を断る(世界ごと止める)。
      public var mode: TrialGateMode?
      /// fence で待たせる物。
      public var holds: TrialHoldsDef?
      /// 待たせた失敗の規則を、門が外れた後にどう判定し直すか。**既定の値を持たない**(下の確かめ)。
      public var resume: TrialResume?
      /// 門が外れた(解放した)ステップで、待たせていた出来事より先に 1 度だけ適用する効果(任意)。
      public var onRelease: [Effect]?
  }
  /// 再開の仕方(オーナーの答え待ち OPEN-T7。物語の条件。本体はどれも書けるようにだけする)。
  public enum TrialResume: Codable, Equatable, Sendable {
      /// 外れたステップから、待たせた規則を普通に判定する。
      case judgeAtRelease
      /// 外れてから hours のゲーム時間は、待たせた規則を判定しない。その後に普通に判定する。
      case grace(hours: Int)
      /// 外れたステップで、待たせた規則の条件に出てくる stat を、待たせ始めた時点の値(`TrialHeld.stats`)に戻してから普通に判定する。
      case restoreStats
  }
  public enum TrialGateMode: String, Codable, Sendable { case fence, freeze }
  public struct TrialHoldsDef: Codable, Equatable, Sendable {
      /// 研究を始める命令を待たせる(理由 `reason.trial.locked` で断る。進めている研究の続きは止めない)。
      public var research: Bool?
      /// 待たせる出来事(起きる条件がそろっても起こさず、待ちの列に積む)。
      public var events: [EventID]?
      /// 待たせる失敗の規則(柵の中では判定しない。オーナーの決定 2026-10-02: 期限の失敗も研究・出来事と同じく待たせる)。
      public var failures: [FailureRuleID]?
  }
  ```
  `ContentValidator`: 条件の中の ID と、`holds.events`・`holds.failures` の ID が在ることを確かめる。**`holds.failures` が空でないのに `resume` が無い門はエラー**(「再開の仕方が書かれていない」。読み込みの検査で落ちるので、答えが無いまま、どれかの案で出ることはない)。`holds.failures` が無い・空の門では `resume` は要らない。
- 区切りに着いた時点の扱い(夜明けまで待つ、など)は**データで書く**: 例えば、区切りの事実を夜明けの出来事が立てるようにする。本体は `when` を見るだけ。
- 権利: `Simulation` に `entitlements: Entitlements` を足す(`public struct Entitlements: Sendable, Equatable { public var fullGame: Bool }`。置き場は RFSim か RFRules。`init(content:systems:entitlements:)` の既定は `.init(fullGame: true)` にして、今のテストとボットは変わらない)。権利は**保存(`WorldState`・`SaveEnvelope`)には入れない**。
- 門の判定: `TrialGate.closed(world, content, entitlements) -> Bool` = 権利が無く、`trialGate` があり、`when` が成り立つ(`ConditionEvaluator.evaluatePure`)。
- fence の間:
  - `holds.research == true` なら、研究を始める命令を `Rejection("reason.trial.locked")` で断る(どの命令が「研究を始める」かを一覧にしてテストで固定する)。
  - `holds.events` の出来事は、起きる条件がそろったステップで起こさず、世界の待ちの列 `WorldState.trial.deferred` に積む。出来事の「起きた」の印も付けない。
  - `holds.failures` の失敗の規則は、柵の間は判定しない(失敗の画面も「失って続ける」も出ない)。条件が初めて成り立ったステップで、待ちの列に `failure` として 1 度だけ積む(待たせた日と、規則の条件に出てくる `stat` の値を写して持つ)。
  - 待ちの列の形(新しい任意の欄。無い保存は空として読む。同じ ID は 1 度だけ積む):
    ```swift
    public struct TrialState: Codable, Equatable, Sendable {
        public var deferred: [TrialHeld] = []
        public var noticed: Bool?
        /// 門が外れたゲームの時刻(外れていなければ nil)。
        public var releasedAt: GameTime?
    }
    public struct TrialHeld: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case event, failure }
        public var kind: Kind
        public var id: String            // EventID か FailureRuleID
        public var since: GameTime       // 待たせ始めた時刻
        public var stats: [StatID: Int]? // failure のとき、待たせ始めた時点の値(規則の条件に出てくる stat だけ)
    }
    ```
  - それ以外(時計・手の作業・生産・運搬・探索・戦闘・ほかの出来事)は、今までどおり進む。
- freeze の間: 時計を進めない(`advance`・`runSteps`・寝るの先読み `forecastSleep` も)。命令を `reason.trial.locked` で断る(今の `reason.scene.prologue` と同じ所で。世界は変えない)。
- 門が閉じたステップで、出来事 `DomainEvent.trialReached` を 1 回だけ出す(画面が案内の札を出すきっかけ)。閉じたかどうかは世界の条件から毎回出せるので、「出した」の印は `WorldState.trial.noticed: Bool?` に持つ(保存に入る。権利ではなく「札を出した」の記録)。
- **門が外れる(解放)**: 「門が一度閉じた(`noticed == true`)・まだ外れていない(`releasedAt == nil`)・今は権利がある」がそろった最初のステップで、1 度だけ次の順に行う。世界は作り直さない。
  1. `releasedAt` に今の時刻を入れる。
  2. `onRelease` の効果を適用する。`resume` が `restoreStats` なら、待たせた規則の stat を写した値に戻す。
  3. 待ちの列の出来事を**積んだ順に**起こす(起こす時点で条件をもう一度見ない。待たせたのは本体なので)。
  4. 待たせていた失敗の規則を、`resume` のとおりに判定し直す(`judgeAtRelease`・`restoreStats` はこのステップから、`grace` は時間がたってから。条件がまだ成り立てば普通の失敗になる)。列を空にする。研究も始められる。出来事 `DomainEvent.trialReleased` を 1 回出す。
  - 同じ口が 2 つの場合を受ける: (a) 携帯で購入・復元して権利が付いた。(b) 門の無い版(Steam の製品版。権利は常にあり)が、体験版の保存(閉じた門と待ちの列を持つ)を初めて読んだ。どちらも最初のステップで同じ手順が 1 度だけ走る。
  - **再開の仕方はまだ決まっていない**(オーナーの答え待ち OPEN-T7。物語の条件)。本体は `TrialResume` の 3 つをどれも書けるようにし、どれも既定にしない。3 つで足りない答えが来たときのために、条件 `trial(test:)`(`TrialTest`: `.released(hoursAtLeast: Int)`・`.held(id: String)`)も足す(失敗の規則の `when` に書ける)。
    - 待たせた日だけでは「値を戻す」型が書けないので、`TrialHeld.stats` で値も写して持つ。時刻の型(猶予)は `since` と `releasedAt` で足りる。
  - 払い戻しで権利が消え、門がもう一度閉じたステップでは `releasedAt` を nil に戻す(次に権利が付いたとき、同じ手順がもう一度走る)。
- 画面の組み立て: `Frame` に `trial: TrialFrame?`(閉じているか・形(fence/freeze)・待っている物の数)を足し、`FrameBuilder` に `entitlements` を渡す口を足す(既定は解放済み)。
- 文言: `reason.trial.locked` と、案内の札の文言 ID(例 `ui.trial.title`・`ui.trial.body`・`ui.trial.buy`・`ui.trial.restore`・`ui.trial.continue`)を公開の層の `text/ja/` に中立の見本で置く(「ここから先は購入で遊べます」程度。物語の語を使わない)。
- テスト(新しいファイル `RFSimTests/TrialGateTests.swift` など。公開の層に、テストの中だけで試験用の門と出来事を重ねる):
  1. `trialGate` の無い内容では、権利が無くても今とまったく同じ(同じ seed・同じ命令で同じ世界)。
  2. fence: 権利無しで区切りの事実を知った後も、時計・手の作業・生産は進む。研究を始める命令は `reason.trial.locked`。`holds.events` の出来事は起きずに列に積まれ(1 度だけ)、ほかの出来事は起きる。`trialReached` は 1 回だけ。
  3. fence → 権利あり: 次のステップで、`onRelease` の効果 → 列の出来事(積んだ順)の順に起き、列が空になり、`releasedAt` が入り、`trialReleased` が 1 回出る。研究が始められる。
  3b. 失敗の規則: 権利無しの柵の中で、`holds.failures` の規則の条件が成り立っても失敗にならず、列に `failure` が 1 度だけ積まれる(`since` と `stats` が入る)。挙げていない規則は今までどおり失敗になる。権利ありになったステップで、条件がまだ成り立てば失敗になる。`resume` の 3 つそれぞれで: `judgeAtRelease` はそのステップで失敗、`grace(hours:)` はその時間まで失敗にならない、`restoreStats` は値が待たせ始めた時点に戻り、戻した値で条件が成り立たなければ失敗にならない。
  3c. 門の無い版で読む: 権利無しで門が閉じ、列を持つ世界を保存し、権利ありの `Simulation` で読み直すと、最初のステップで 3 と同じ手順が 1 度だけ走る。2 度目のステップでは走らない。
  4. freeze: 時計が進まない・命令が断られる・寝るの先読みも止まる。権利ありで同じ世界が続く。
  5. 保存: 待ちの列(出来事と失敗の両方。`since`・`stats` も)のある世界を保存して読み直すと、列が残る(体験版の保存が製品版で続く前提)。`trial` の欄の無い古い保存は空として読む。凍らせた見本 `save-v1-dev-*.json` はそのまま読める。
  6. JSON: `trialGate` の有無・`mode` の有無(既定 fence)・`holds` の有無の全部が読める。`holds.failures` があって `resume` が無い門は確かめでエラー。

### B.2 権利の確かめ(アプリ。macOS の CI)
- `StoreService` を StoreKit 2 の実装 `StoreKitStoreService` にする(今の `UnavailableStoreService` は、StoreKit が使えないとき・プレビュー用に残す)。
  - 品: `ProductID.fullGame = "reforge.fullgame"`(追加の章 `reforge.chapter2` は X-01 で足す。今は足さない)。
  - 権利: `Transaction.currentEntitlements` を読み、`.verified` で `revocationDate == nil` の取引の品の ID の集まり。**通信は要らない**(端末の署名付きの記録を端末の上で確かめる)。`.unverified` は権利にしない。
  - 読み直す時: 起動時・前に出たとき(`scenePhase == .active`)・`Transaction.updates` が来たとき(`finish()` してから)・購入と復元の後。
  - 購入: `Product.products(for:)` → `purchase()`。結果が `.verified` なら `finish()` して読み直す。値段は `Product.displayPrice` をそのまま出す(アプリは値段を持たない)。
  - 復元: `AppStore.sync()` の後に読み直す。
  - **アプリが書く印を権利の根拠にしない**(`UserDefaults` に権利を書かない。G §1.2)。
- ビルドの設定で門を開ける口(リーダーの指示 2026-10-02。dev の版をどうするかはオーナーの答え待ち):
  - `Info.plist` の値 `ReForgeTrialGateOpen`(Bool)を、ビルドの設定 `REFORGE_TRIAL_GATE_OPEN`(`project.yml` の設定。**既定 `NO`**)から入れる。`YES` のビルドでは、アプリが本体に渡す `Entitlements.fullGame` を常に `true` にする(StoreKit の権利とは別の口。権利の表示は StoreKit のまま)。
  - 既定のビルド(release も含む)は `NO`。**dev の版(SideStore で配る `releases/download/dev` の ipa)は `YES`**(オーナーの決定 2026-10-02。店に出すまで。出すときに決め直す)。CI の dev のジョブの xcodebuild に `REFORGE_TRIAL_GATE_OPEN=YES` を付ける。ほかのジョブ(単体テスト・画面の写真・release)は `NO` のまま。
  - 口の値はアプリの起動時に 1 度だけ読み、実行中に変えられない(`UserDefaults` や設定の画面からは変えられない)。
  - テスト: 既定のビルドで値が `NO`(`Bundle.main` から読めること)を `ReForgeTests` で確かめる。
- `AppModel` が権利(`Entitlements`)を持ち、`GameStore` の `Simulation`・`FrameBuilder` に渡す。権利が変わったら作り直して渡す(世界はそのまま)。
- `.storekit` の設定ファイル(`ReForge/Resources/ReForge.storekit` など。`reforge.fullgame` 1 品)を置き、`ReForgeTests` で StoreKitTest(`SKTestSession`)を使って確かめる: 買う → 権利が付く、払い戻し(`refundTransaction`)→ 権利が消える、復元、家族共有の取引も権利にする、`.unverified` は権利にしない(作れれば)。macOS の CI でだけ回る。

### B.3 区切りの案内(アプリ)
- `Frame.trial` が閉じたとき(`trialReached` の出来事)に、地図の上に案内の札を 1 枚出す(`InkCard` の作り。確認のダイアログ・閉じるまで進めないシート・数え下ろしは使わない)。文言は B.1 の `ui.trial.*`(公開の見本。非公開の層が本物の文を置く)。
- ボタン: 「購入」(値段を添える)・「購入を復元」・fence なら「この章を続ける」(札を閉じて遊び続ける)/ freeze なら「タイトルへ」。購入・復元で権利が付いたら、札を閉じてそのまま続く。
- fence で札を閉じた後は、研究の画面と設定の購入の所に、待っていることを 1 行で出す(押すと札をもう一度出す)。
- 区切りより前の本編の場面・クレジットには、購入の案内を出さない(G §1.3)。
- 画面の写真に 1 枚足してよい(`ScreenshotMode` に `trial`)。

### B.4 設定の購入の所
- 節の題「購入」。行: 「本編」(解放済みなら「解放済み」、まだなら値段と「購入」)・「購入を復元」(結果を 1 行で出す。今の `restoreButton` の識別子を残す)。
- 文言は今の決まり(`Text("…")` のリテラル・`gen-xcstrings`)で書く。

## C. 区切りの位置
- 位置そのもの(`trialGate` の条件)と、待たせる物の一覧(`holds`)は、この作業では決めない。game-designer の候補からオーナーが決め、U14 が非公開の層に置く。公開の層の本物の `bundle.json` には置かない(試験の門はテストの中で重ねる)。
- だから、この作業が入った時点では、どのビルドでも門は閉じない(今までどおり最後まで遊べる)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。テストの数が減らない(広告のテストがあれば、消した分を報告する)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-store-metadata.py`・`check-public-spoilers.py`。
- `git grep -n -i -E "広告|AdSlot|AdBanner|adProvider|adsRemoved|remove_ads|removeAds|AdMob|ATTrackingManager|NSUserTracking"` が空(`docs/art/README.md` の絵の言い回し「広告のような笑顔」と、`docs/briefs/S-03-*`・過去の説明書は除く)。
- 統合担当が非公開の層を重ねて回し、macOS の CI(ci/integration)でアプリのビルド・単体テスト・StoreKitTest を回す。
- 凍らせた見本は作り直さない・飛ばさない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
