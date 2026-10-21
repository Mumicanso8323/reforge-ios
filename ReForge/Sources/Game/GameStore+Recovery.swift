import Foundation
import ReForgeEngine

/// 保存・ゲームオーバーの 4 択・手動セーブとロード(D-save.md §2・§3)。担当: U18。
/// 確認のダイアログは出さない。復帰は実行後に取り消しの帯で戻せる。
extension GameStore {
    /// 保存の帳簿(規則は本体の SaveBook)。
    var book: SaveBook {
        SaveBook(storage: saves, content: contentStamps)
    }

    var recovery: Recovery {
        let c = content
        return Recovery(content: c, book: book, newWorld: { GameBootstrap.newWorld(content: c, seed: $0) })
    }

    /// 夜明けの自動セーブ。
    func saveDawn() async {
        await settleUndo()  // 走り出した「戻す」を書いてから保存する
        do {
            let data = try await host.dawnSaveData(stamps: contentStamps)
            try await saveWriter.autosaveDawn(data)
        } catch {
            log.error("dawn save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// 4 択(決まった順)。走行が終わっていなければ空。
    func recoveryChoices() async -> [RecoveryChoice] {
        let w = await host.world
        return (try? recovery.choices(for: w)) ?? []
    }

    /// 4 択の 1 つを実行し、世界を差し替える。失敗したら理由を 1 行で返す(画面は札の中に出す)。
    @discardableResult
    func recover(_ option: RecoveryOption, target: SaveSlot? = nil) async -> String? {
        await settleUndo()
        let failed = await host.world
        do {
            let r = try recovery.perform(option, failed: failed, target: target, newSeed: UInt64.random(in: .min ... .max))
            await replaceWorld(r.world)
            return nil
        } catch RecoveryError.unavailable(_, let reason) {
            return await host.describe(Rejection(reason))
        } catch {
            return String(describing: error)
        }
    }

    /// 失敗からの復帰はすぐ反映し、短時間だけ失敗直前へ戻せるようにする。
    @discardableResult
    func recoverUndoable(_ option: RecoveryOption, target: SaveSlot? = nil, label: String) async -> String? {
        commitTimedUndo()
        await settleUndo()
        let before = await host.world
        let problem = await recover(option, target: target)
        if problem == nil { beginTimedUndo(world: before, label: label, pausesClock: true) }
        return problem
    }

    // MARK: - 手動セーブ・ロード

    /// セーブ地点の一覧(夜明けの新しい順 → 手動の番号順)。
    func savePoints() -> [SavePoint] { (try? book.savePoints()) ?? [] }

    /// セーブ地点の一覧を自動(夜明け)と手動の 2 つに分けたもの(D §7.4)。
    func savePointGroups(activeOnly: Bool) -> SavePointGroups {
        (try? book.savePointGroups(activeOnly: activeOnly)) ?? SavePointGroups(auto: [], manual: [])
    }

    /// 手動セーブ(確認なしで上書き。枠は 3 つあるので戻せる)。
    func saveManual(_ index: Int) async {
        guard (0..<SavePolicy.manualSlots).contains(index) else { return }
        await settleUndo()  // 走り出した「戻す」を書いてから保存する
        do {
            let data = try await host.saveData(slot: .manual(index: index), stamps: contentStamps)
            try await saveWriter.write(data, slot: .manual(index: index))
        } catch {
            log.error("manual save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// セーブ地点からロードする(走行の途中でも)。読めない・終わった走行の保存なら何もしない。
    @discardableResult
    func load(_ slot: SaveSlot) async -> Bool {
        guard let e = try? book.load(slot), e.summary.active else { return false }
        try? book.adoptTimeline(e.world)
        await replaceWorld(e.world)
        await saveResume()
        return true
    }

    // MARK: - 置くモード

    /// 建てる物を選んだ: 地図に戻り、ノアの足元に照準を出す。
    func beginPlacing(_ kind: StructureKindID) {
        placing = kind
        requestedTab = .map
        let at = focus ?? GridPoint(mapView.size.width / 2, mapView.size.height / 2)
        Task { preview = await host.placementPreview(kind, at: at) }
    }

    /// 照準の場所に建てる(確認は出さない。片付ければ材料は戻る)。
    func confirmPlacing() {
        guard let p = preview, p.placeable else { return }
        placing = nil
        preview = nil
        send(p.buildCommand)
    }

    func cancelPlacing() {
        placing = nil
        preview = nil
    }

    // MARK: - 残骸のパネル

    /// 残骸の資料をパネルとして開く(地図の上の札。時計は止めない)。
    func openPanel(_ id: DocumentID) {
        Task { panel = await host.document(id) }
    }

    func closePanel() { panel = nil }

    // MARK: - 戦闘

    func setStance(_ s: BattleState.Stance, in battle: BattleBand) { send(battle.stanceCommand(s)) }
    func retreat(_ battle: BattleBand) { send(battle.retreatCommand) }
    func setDefaultStance(_ s: BattleState.Stance) { send(.combat(.setDefaultStance(stance: s))) }
}
