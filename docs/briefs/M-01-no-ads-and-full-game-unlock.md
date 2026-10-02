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
- 内容の定義: `ContentDB` に任意の `trialGate: TrialGateDef?` を足す。`TrialGateDef { when: Condition }`。JSON は内容の束の上の段のキー `trialGate`(`bundle.json` と同じ並び。ほかの層で置き換えられる)。無ければ門は無い(今までのデータはそのまま)。`ContentValidator` は条件の中の ID を今の条件と同じに確かめる。
- 権利: `Simulation` に `entitlements: Entitlements` を足す(`public struct Entitlements: Sendable, Equatable { public var fullGame: Bool }`。置き場は RFSim か RFRules。`init(content:systems:entitlements:)` の既定は `.init(fullGame: true)` にして、今のテストとボットは変わらない)。**保存(`WorldState`・`SaveEnvelope`)には入れない**。
- 門の判定: `TrialGate.locked(world, content, entitlements) -> Bool` = 権利が無く、`trialGate` があり、その条件が成り立つ(`ConditionEvaluator.evaluatePure`)。
- 止める: 門が閉じている間は、
  - `apply`: 命令を `Rejection("reason.trial.locked")` で断る(今の `reason.scene.prologue` と同じ所で。世界は変えない)。ただし画面の出し入れだけの命令(あれば)や、保存に関わらない問い合わせは断らない。断ってよい命令の一覧を作り、テストで固定する。
  - `advance`・`runSteps`・寝るの先読み: 時計を進めない(ステップを回さない)。
  - 門が閉じたその 1 ステップで、出来事 `DomainEvent.trialLocked` を 1 回だけ出す(画面が案内の 1 枚を出すきっかけ)。条件が成り立ったステップの反応(効果・場面の始まり)はそのステップの中で済ませてから止める。
- 画面の組み立て: `Frame` に `trialLocked: Bool` を足し、`FrameBuilder` が `TrialGate.locked` から入れる(`FrameBuilder` にも `entitlements` を渡す口を足す。既定は解放済み)。
- 文言: `reason.trial.locked` と、案内の 1 枚の文言 ID(例 `ui.trial.title`・`ui.trial.body`・`ui.trial.buy`・`ui.trial.restore`)を公開の層の `text/ja/` に中立の見本で置く(「ここから先は購入で遊べます」程度。物語の語を使わない)。
- テスト(新しいファイル `RFSimTests/TrialGateTests.swift` など):
  1. `trialGate` の無い内容では、権利が無くても今とまったく同じ(同じ seed・同じ命令で同じ世界)。
  2. 公開の層に試験用の門(例: 試験の事実 `fact.test.trial_end` を知ったら)を一時的に重ね、権利無しでは事実を知ったステップで止まる: 時計が進まない・命令が `reason.trial.locked` で断られる・`trialLocked` の出来事が 1 回・`Frame.trialLocked == true`。
  3. 同じ世界を権利ありの `Simulation` に渡すと、そのまま続く(世界を作り直さない)。
  4. 止まった世界を保存して読み直しても、権利無しなら止まったまま、権利ありなら続く(保存の形は変わらない。凍らせた見本 `save-v1-dev-*.json` はそのまま読める)。
  5. 寝るの先読み(`forecastSleep`)も門で止まる。
  6. JSON: `trialGate` の有無の両方が読める。

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
  - 既定のビルド(release も含む)は `NO`。dev の版を `YES` にするかは、CI の dev のジョブの 1 行(`xcodebuild … REFORGE_TRIAL_GATE_OPEN=YES`)で切り替えられるようにし、**この作業では `NO` のまま**にする(ジョブの行はコメントで用意だけ)。
  - 口の値はアプリの起動時に 1 度だけ読み、実行中に変えられない(`UserDefaults` や設定の画面からは変えられない)。
  - テスト: 既定のビルドで値が `NO`(`Bundle.main` から読めること)を `ReForgeTests` で確かめる。
- `AppModel` が権利(`Entitlements`)を持ち、`GameStore` の `Simulation`・`FrameBuilder` に渡す。権利が変わったら作り直して渡す(世界はそのまま)。
- `.storekit` の設定ファイル(`ReForge/Resources/ReForge.storekit` など。`reforge.fullgame` 1 品)を置き、`ReForgeTests` で StoreKitTest(`SKTestSession`)を使って確かめる: 買う → 権利が付く、払い戻し(`refundTransaction`)→ 権利が消える、復元、家族共有の取引も権利にする、`.unverified` は権利にしない(作れれば)。macOS の CI でだけ回る。

### B.3 区切りの案内(アプリ)
- `Frame.trialLocked` のとき、地図の上に案内の 1 枚(札。`InkCard` の作り)を出す: 文言は B.1 の `ui.trial.*`(公開の見本・非公開の層が本物の文を置く)。ボタンは「購入」(値段を添える)・「購入を復元」・「タイトルへ」。購入・復元で権利が付いたら札を閉じて、そのまま続く。
- 区切りより前の本編の場面・クレジットには、購入の案内を出さない(G §1.3)。
- 画面の写真に 1 枚足してよい(`ScreenshotMode` に `trialLocked`)。

### B.4 設定の購入の所
- 節の題「購入」。行: 「本編」(解放済みなら「解放済み」、まだなら値段と「購入」)・「購入を復元」(結果を 1 行で出す。今の `restoreButton` の識別子を残す)。
- 文言は今の決まり(`Text("…")` のリテラル・`gen-xcstrings`)で書く。

## C. 区切りの位置
- 位置そのもの(`trialGate` の条件)は、この作業では決めない。game-designer の候補からオーナーが決め、U14 が非公開の層に置く。公開の層の本物の `bundle.json` には置かない(試験の門はテストの中で重ねる)。
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
