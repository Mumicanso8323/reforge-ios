import RFContent
import RFKernel
import RFMatter
import RFRules
import RFWorld

/// 発明(CORE-02)。試作(手持ちの材料を実際に使い、RFMatter の ProcessChain で計算)、実験ノート(所見・
/// 出典つきの書き留め・図鑑)、ヒント(仲間の関係ランクと条件)、ライン札。工程表は設計画面と同じ部品で開く。
///
/// 書いてよい切れ端: invention / notebook。乱数の流れ: .invention(R1 は使わない)。
/// 受けるコマンド: .invention(.trial / .makeDesign / .discardDesign)。
///
/// - 試作: `Trials`。結果はノートに載り、最初の製錬は唯一品と来歴の印(`InventionTags`)を残す
///   (最初の鉄の場面は出来事の担当が `trialed` の引き金で起こす)。
/// - 推理の導線 5 種(order.md §5.4): 端末の断片・仲間の知識・手が知っていた手順・図鑑の空欄は `HintDef`(`Hints`)、
///   失敗知見は試作の所見、ノアの手は `HandSense`。ノートは事実と出典だけを書き、規則をまとめない。
/// - 工程表: `Sheets`(ライン札・試作・下書き・コンテンツの記録を同じ形で)。図鑑: `Codex`。
public struct InventionSystem: SimSystem {
    public let name = "invention"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .invention(let c) = command else { return .notMine }
        switch c {
        case .trial(let input, let quantity, let steps):
            return Trials.run(input: input, quantity: quantity, steps: steps, &ctx)
        case .makeDesign(let steps):
            return Self.makeDesign(steps, &ctx)
        case .discardDesign(let id):
            guard ctx.world.invention.designs.removeValue(forKey: id) != nil else {
                return .rejected(Rejection(InventionReasons.noDesign))
            }
            ctx.changes.mark(.notebook)
            return .done
        }
    }

    public func step(_ ctx: inout StepContext) {
        // 状態だけで成り立つ手がかり(関係のランクなど)を、最初のステップと以後 1 時間ごとに見回る
        if (ctx.world.clock.now.seconds - SimStep.gameSeconds) % 3600 == 0 { Hints.deliver(&ctx, trigger: nil) }
    }

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        guard !Hints.ignores(event) else { return }
        Hints.deliver(&ctx, trigger: event.record)
    }

    /// 並びをライン札にする。同じ並びを試したことがあれば、その結果を札の見込みにする(新しい試作を優先)。
    static func makeDesign(_ steps: [ProcessStep], _ ctx: inout StepContext) -> CommandResult {
        if let r = InventionChecks.steps(steps, ctx.world) { return .rejected(r) }
        let trial = ctx.world.notebook.trials.last { $0.steps == steps }
        let id = ctx.world.newEntityID()
        let rec = ctx.record(.designed, .design(id), actor: .noah, inputs: trial.map { [$0.record] } ?? [],
                             detail: ["steps": .int(Int64(steps.count))])
        ctx.world.invention.designs[id] = LineDesign(
            id: id, steps: steps, origin: rec, expected: trial?.outcome.product, trial: trial?.record)
        ctx.changes.mark(.notebook)
        ctx.emit(.designed(design: id, record: rec))
        return .done
    }
}
