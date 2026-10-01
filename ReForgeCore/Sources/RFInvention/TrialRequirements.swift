import RFContent
import RFKernel
import RFMatter
import RFRules
import RFWorld

/// 試作に要る設備(発明をマップの上の物とつなぐ。原作の場面「石を積んで炉を作り、火を入れて最初の鉄」)。
///
/// 段ごとの条件はコンテンツのモジュールの定義(`ModuleDef.trial`)が決め、無ければ既定:
/// - 炉(熱する段): 炉を置いてある(生産の担当の配置)。焚き火台の上位などの建造物で足りるなら、コンテンツで条件を書き換える。
/// - 水槽(冷やす段): 水槽を置いてあるか、ノアが水辺に接している。
/// - ほかの段: 条件なし(手と道具でできる)。
/// 条件は RFRules の Condition で評価する(乱数は引かない)。満たさなければ、その条件の理由で断る。
public enum TrialRequirements {
    public static let needsFurnace: TextID = "reason.invention.needs_furnace"
    public static let needsQuench: TextID = "reason.invention.needs_quench"

    public static func defaults(for module: ModuleKindID) -> TrialRequirement? {
        switch module {
        case .furnace:
            return TrialRequirement(when: .placedCount(module: .furnace, structure: nil, atLeast: 1), reason: needsFurnace)
        case .quenchTank:
            return TrialRequirement(
                when: .any(of: [.placedCount(module: .quenchTank, structure: nil, atLeast: 1),
                                .nearTerrain(place: .person(id: .noah), tag: "water", radius: 1)]),
                reason: needsQuench)
        default:
            return nil
        }
    }

    public static func requirement(for module: ModuleKindID, content: ContentDB) -> TrialRequirement? {
        content.modules[module]?.trial ?? defaults(for: module)
    }

    /// 並びの段のうち、条件を満たさない最初のもの(段の順)。満たせば nil。
    public static func check(_ steps: [ProcessStep], world: WorldState, content: ContentDB) -> Rejection? {
        var seen: Set<ModuleKindID> = []
        for s in steps where seen.insert(s.module).inserted {
            guard let req = requirement(for: s.module, content: content) else { continue }
            if ConditionEvaluator.evaluatePure(req.when, world: world, content: content) != true {
                return Rejection(req.reason, detail: ["module": .string(s.module.rawValue)])
            }
        }
        return nil
    }
}
