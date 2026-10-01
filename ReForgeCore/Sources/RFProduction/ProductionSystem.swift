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
        case .convertPlacements(let from, let to, let cause):
            return Placing.convert(from: from, to: to, cause: cause, &ctx)
        case .destroyFromEffect(let near, let radius, let module, let max, let cause):
            for id in Destruction.targets(near: near, radius: radius, max: max, in: ctx.world, where: { p in
                guard let k = p.moduleKind else { return false }
                return module.map { $0 == k } ?? true
            }) { Destruction.destroy(id, cause: cause, &ctx) }
            return .done
        case .repair(let placement):
            return Placing.repair(placement, &ctx)
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
    /// 直すものが壊れていない(U16)。
    public static let notBroken: TextID = "reason.placement.not_broken"
    // 有限の品
    public static let finiteNotUsable: TextID = "reason.finite.not_usable"
    public static let finiteAlreadyUsed: TextID = "reason.finite.already_used"
    public static let finiteMissing: TextID = "reason.finite.missing"
    // 止まった理由
    public static let noInput: TextID = "reason.module.no_input"
    public static let noAux: TextID = "reason.module.no_aux"
    /// 電力が来ていない(U16)。
    public static let noPower: TextID = "reason.module.no_power"
    /// 人が付いていない(人の手で回す発電機。U16)。
    public static let noWorker: TextID = "reason.module.no_worker"
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

    /// 人の作業の速さ(千分率)。空腹・状態・精神力で下がる(U4 の survival.work。手作業と付いている仲間に掛かる)。
    public static func workSpeed(_ p: PersonID, _ w: WorldState) -> Int { w.survival.workPermille(for: p) }

    /// 付いている仲間がいるときのモジュールの速さ(千分率)。
    /// 本体は RFCrew の PersonState.workSpeed(1000 + 専門一致 300 + 関係ランク 3 以上 100 + 思想と配属の印)。
    /// それが無いとき(RFCrew を回さない試験など)は、専門と関係ランクだけをここで数える。
    /// それに作業の速さ(空腹など)を掛ける。範囲の効果はモジュールの側で掛ける。
    /// 思想が配属と合わない人・空腹の人は 1000 を下回ってよい(MECH-05)。
    public static func operatorSpeed(_ op: PersonID, module kind: ModuleKindID, _ w: WorldState, _ content: ContentDB)
        -> Int
    {
        let base: Int
        if let s = w.people[op]?.workSpeed {
            base = s
        } else {
            var bonus = 0
            if let sp = content.modules[kind]?.specialty, content.people[op]?.specialties.contains(sp) == true {
                bonus += specialtyBonusPermille
            }
            if (w.people[op]?.relation.rank ?? 0) >= rankForBonus { bonus += rankBonusPermille }
            base = 1000 + bonus
        }
        return base * workSpeed(op, w) / 1000
    }
}
