import RFContent
import RFKernel
import RFMatter
import RFRules
import RFWorld

/// ラインと手作業(CORE-04・05)。モジュールを置く(置ける場所の規則)・動かす・片付ける(材料は全部戻る)、
/// 隣接と向きでつながる、1 回の処理(RuleBook の 1 工程)、止まった理由、1 日あたりの入出、仲間が付くと速い、
/// 手作業(押し続けて 1 単位)、手作業から T1 への昇格、有限の品を使う/取っておく。
///
/// 書いてよい切れ端: placements(モジュール・手作業の途中)・map の鉱脈の残り。乱数の流れ: .production。
/// 受けるコマンド: .production(...)。離れた所への運搬は RFLogistics(同じ担当)。
///
/// 1 ステップの順:
/// 1. 拠点の中のモジュールは蓄えから燃料・混ぜ物を取る。付いている仲間を配属から写す。
/// 2. 各モジュールの 1 回の処理を進める(止まっていれば理由を出す)。
/// 3. できた物を隣の直結へ渡す。拠点の中で行き先の無い物は蓄えへ入れる(入れると冷える = 並びの最後の規則)。
/// 4. 押し続けている手作業を進める。
public struct ProductionSystem: SimSystem {
    public let name = "production"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .production(let c) = command else { return .notMine }
        switch c {
        case .placeFromDesign(let design, let stepIndex, let at, let facing):
            return Placing.placeFromDesign(design, stepIndex: stepIndex, at: at, facing: facing, &ctx)
        case .place(let module, let at, let facing):
            return Placing.place(module, step: nil, design: nil, stepIndex: nil, at: at, facing: facing, &ctx)
        case .move(let placement, let to, let facing):
            return Placing.move(placement, to: to, facing: facing, &ctx)
        case .dismantle(let placement):
            return Placing.dismantle(placement, &ctx)
        case .handwork(let id, let input, let holding):
            return Handwork.handle(id, input: input, holding: holding, person: .noah, &ctx)
        case .useFinite(let placement, let stock):
            return Placing.useFinite(placement, stock: stock, &ctx)
        }
    }

    public func step(_ ctx: inout StepContext) {
        Modules.step(&ctx)
        Handwork.step(&ctx)
    }

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        if case .dawn = event {
            Modules.rollDay(&ctx)
            Placing.noteKeptFinites(&ctx)
        }
    }
}

/// 生産の決まった値と理由のキー(文は文字列表。画面は足元カードに 1 行)。
public enum ProductionText {
    // 置く
    public static let unknownModule: TextID = "reason.place.unknown_module"
    public static let locked: TextID = "reason.place.locked"
    public static let outOfMap: TextID = "reason.place.out_of_map"
    public static let occupied: TextID = "reason.place.occupied"
    public static let terrain: TextID = "reason.place.terrain"
    public static let needsDeposit: TextID = "reason.place.needs_deposit"
    public static let depositDepleted: TextID = "reason.place.deposit_depleted"
    public static let needsWater: TextID = "reason.place.needs_water"
    public static let noMaterials: TextID = "reason.place.no_materials"
    public static let unknownDesign: TextID = "reason.design.unknown"
    public static let noSuchStep: TextID = "reason.design.no_step"
    public static let notAModule: TextID = "reason.placement.not_module"
    public static let noSuchPlacement: TextID = "reason.placement.unknown"
    // 有限の品
    public static let finiteNotUsable: TextID = "reason.finite.not_usable"
    public static let finiteAlreadyUsed: TextID = "reason.finite.already_used"
    public static let finiteMissing: TextID = "reason.finite.missing"
    // 止まった理由
    public static let noInput: TextID = "reason.module.no_input"
    public static let noAux: TextID = "reason.module.no_aux"
    public static let outputFull: TextID = "reason.module.output_full"
    public static let depleted: TextID = "reason.module.depleted"
    public static let noDeposit: TextID = "reason.module.no_deposit"
    // 手作業
    public static let handworkUnknown: TextID = "reason.handwork.unknown"
    public static let handworkLocked: TextID = "reason.handwork.locked"
    public static let handworkNotNow: TextID = "reason.handwork.not_now"
    public static let handworkNoActor: TextID = "reason.handwork.no_actor"
    public static let handworkNeedsStation: TextID = "reason.handwork.needs_station"
    public static let handworkNeedsDeposit: TextID = "reason.handwork.needs_deposit"
    public static let handworkNoInput: TextID = "reason.handwork.no_input"
    public static let handworkOutOfReach: TextID = "reason.handwork.out_of_reach"
    public static let handworkNoEffect: TextID = "reason.handwork.no_effect"
    public static let handworkNoAux: TextID = "reason.handwork.no_aux"
}

/// 生産の仮の数(R1。order.md §5.6)。
public enum ProductionRules {
    /// 手作業 1 回押すのにかかるゲーム秒の既定(昼の実時間 1 秒)。
    public static let defaultPressSeconds = 160
    /// 仲間が付いたときの速さ: 専門が合えば +30%、関係ランク 3 以上なら +10%(PlacedModule.cs)。
    public static let specialtyBonusPermille = 300
    public static let rankBonusPermille = 100
    public static let rankForBonus = 3
    /// 付いている仲間とみなす距離(チェビシェフ)。
    public static let operatorReach = 1
    /// 置いた物の範囲の効果の半径の既定(定義に半径が無いとき)。
    public static let defaultAuraRadius = 3
    /// 有限の品の残りの満タン(千分率)。
    public static let finiteFull = Milli(raw: 1000)

    /// 人の作業の速さ(千分率)。空腹・状態・精神力で下がる(U4 の生存が持つ値)。
    /// U4 の `survival.work` が境界に入ったらそこを読む。それまでは 1000。
    public static func workSpeed(_ p: PersonID, _ w: WorldState) -> Int { 1000 }
}
