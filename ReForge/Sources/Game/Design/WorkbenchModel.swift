import Foundation
import Observation
import SwiftUI
import ReForgeEngine

/// 設計・ノートのタブの画面側の状態(下書き・選んだ物・開いている頁)。本体の世界状態には入れない(C-engine-ui.md §6)。
/// 本体からは GameHost の引き出し(designBench・notebook・sheet・document)で読み、操作は Command を送るだけ。
@MainActor
@Observable
final class WorkbenchModel {
    // MARK: 下書き
    private(set) var steps: [ProcessStep] = []
    /// 試す物(在庫の山)。
    var input: StockSelector?
    var quantity = 1
    /// 段に入れる物を足す先の段(nil なら最後の段)。
    var selectedStep: Int?

    // MARK: 本体から引いたもの
    private(set) var bench: DesignBench?
    private(set) var draft: ProcessSheet?
    /// 直前の試作の表(結果カードつき)。
    private(set) var lastTrial: ProcessSheet?
    private(set) var notebook: NotebookPage?
    /// 断られた理由など(タブの中に 1 行。ダイアログは出さない)。
    private(set) var message: String?

    // MARK: ノートの頁(シートを出さず、タブの中で開いて「もどる」で閉じる)
    enum Page: Equatable {
        case index
        case sheet(ProcessSheet.Source)
        case document(DocumentID)
    }
    var page: Page = .index
    private(set) var openSheet: ProcessSheet?
    private(set) var openDocument: DocumentPage?
    /// 答えを置こうとしている行と候補。
    private(set) var answering: (row: String, candidates: [AnswerCandidate])?

    // MARK: - 読み直し

    func reload(_ store: GameStore) async {
        let host = store.host
        bench = await host.designBench()
        notebook = await host.notebook()
        if let input, !(bench?.materials.contains { $0.selector == input } ?? false) { self.input = nil }
        if input == nil { input = bench?.materials.first?.selector }
        await reloadDraft(store)
        switch page {
        case .index:
            openSheet = nil
            openDocument = nil
        case .sheet(let s):
            openSheet = await host.sheet(s)
        case .document(let d):
            openDocument = await host.document(d)
        }
    }

    private func reloadDraft(_ store: GameStore) async {
        draft = steps.isEmpty ? nil : await store.host.sheet(.draft(steps: steps, input: input))
    }

    // MARK: - 下書きの操作(戻せる操作なので確認は出さない)

    func append(_ module: ModuleKindID, _ store: GameStore) async {
        steps.append(ProcessStep(module))
        selectedStep = steps.count - 1
        await reloadDraft(store)
    }

    func remove(_ i: Int, _ store: GameStore) async {
        guard steps.indices.contains(i) else { return }
        steps.remove(at: i)
        selectedStep = steps.isEmpty ? nil : min(i, steps.count - 1)
        await reloadDraft(store)
    }

    func move(_ i: Int, by d: Int, _ store: GameStore) async {
        let j = i + d
        guard steps.indices.contains(i), steps.indices.contains(j) else { return }
        steps.swapAt(i, j)
        selectedStep = j
        await reloadDraft(store)
    }

    /// 段に物を入れる(同じ物をもう一度選ぶと外す)。
    func toggleAdditive(_ item: ItemID, _ store: GameStore) async {
        guard let i = selectedStep ?? steps.indices.last else { return }
        if let k = steps[i].inputs.firstIndex(where: { $0.item == item }) {
            steps[i].inputs.remove(at: k)
        } else {
            steps[i].inputs.append(RecipeLot(item))
        }
        await reloadDraft(store)
    }

    func clear(_ store: GameStore) async {
        steps = []
        selectedStep = nil
        lastTrial = nil
        await reloadDraft(store)
    }

    func choose(input sel: StockSelector, _ store: GameStore) async {
        input = sel
        await reloadDraft(store)
    }

    /// 札を下書きに写す(並べ替えて別の札にできる)。
    func load(plate: DesignBench.Plate, _ store: GameStore) async {
        guard let s = await store.host.world.invention.designs[plate.design]?.steps else { return }
        steps = s
        selectedStep = nil
        await reloadDraft(store)
    }

    // MARK: - 本体へ送る

    func trial(_ store: GameStore) async {
        guard let input else { return }
        let before = await store.host.world.notebook.trials.last?.record
        message = await store.perform(.invention(.trial(input: input, quantity: max(1, quantity), steps: steps)))
        let rec = await store.host.world.notebook.trials.last?.record
        if let rec, rec != before { lastTrial = await store.host.sheet(.trial(rec)) }
        await reload(store)
    }

    func makePlate(_ store: GameStore) async {
        message = await store.perform(.invention(.makeDesign(steps: steps)))
        await reload(store)
    }

    func discard(_ plate: DesignBench.Plate, _ store: GameStore) async {
        message = await store.perform(.invention(.discardDesign(design: plate.design)))
        await reload(store)
    }

    // MARK: - ノートの頁

    func open(_ p: Page, _ store: GameStore) async {
        page = p
        answering = nil
        // 記録を開いたことは本体に送る(開いたこと自体が引き金になる。U15)
        switch p {
        case .sheet(.record(let sid)): message = await store.perform(.narrative(.openSheet(sheet: sid, slot: nil)))
        case .sheet(.recordEntry(let sid, let slot)):
            message = await store.perform(.narrative(.openSheet(sheet: sid, slot: slot)))
        default: break
        }
        await reload(store)
    }

    func back(_ store: GameStore) async {
        // 記録の 1 件からは記録の表へ、それ以外は目次へ
        if case .sheet(.recordEntry(let sid, _)) = page {
            page = .sheet(.record(sid))
        } else {
            page = .index
        }
        answering = nil
        await reload(store)
    }

    func beginAnswer(sheet: SheetID, row: String, _ store: GameStore) async {
        if answering?.row == row {
            answering = nil
            return
        }
        answering = (row, await store.host.answerCandidates(sheet, row: row))
    }

    func place(_ c: AnswerCandidate, sheet: SheetID, _ store: GameStore) async {
        guard let row = answering?.row else { return }
        message = await store.perform(.narrative(.placeAnswer(sheet: sheet, row: row, record: c.record)))
        answering = nil
        await reload(store)
    }

    /// 装置で技能を書き足す(skill nil = この人には使わない)。
    func imprint(sheet: SheetID, person: PersonID, skill: SkillID?, _ store: GameStore) async {
        message = await store.perform(.narrative(.imprint(sheet: sheet, person: person, skill: skill)))
        await reload(store)
    }

    /// 名簿を締める(出発)。
    func lockManifest(sheet: SheetID, _ store: GameStore) async {
        message = await store.perform(.narrative(.lockManifest(sheet: sheet)))
        await reload(store)
    }

    func board(sheet: SheetID, person: PersonID, aboard: Bool, _ store: GameStore) async {
        message = await store.perform(.narrative(.setBoarding(sheet: sheet, person: person, aboard: aboard)))
        await reload(store)
    }
}

/// ノアの手の見当の言い回し(画面の固定文言。数そのものは出さない)。
enum SenseWords {
    /// 見当の十分率(0〜10。四捨五入)。
    static func tenths(_ percent: Int) -> Int { min(10, max(0, (percent + 5) / 10)) }

    /// 見当の言い回し(文言のカタログのキー)。
    static func phrase(_ percent: Int) -> Text {
        let k = tenths(percent)
        if k == 0 { return Text("ほとんど無い") }
        if k == 10 { return Text("混じり気がほぼ無い") }
        return Text("\(k)割くらい")
    }
}
