import RFContent
import RFKernel
import RFWorld

/// Rights are an execution environment, never saved with WorldState.
public struct Entitlements: Sendable, Equatable {
    public var fullGame: Bool
    public init(fullGame: Bool = true) { self.fullGame = fullGame }
}

public enum TrialGate {
    /// 一度区切りに届いた(noticed)世界は、条件が後で崩れても権利が付くまで閉じたまま(買わずに開かない)。
    public static func closed(_ world: WorldState, _ content: ContentDB, _ entitlements: Entitlements) -> Bool {
        guard !entitlements.fullGame, let gate = content.trialGate else { return false }
        if world.trial?.noticed == true { return true }
        return ConditionEvaluator.evaluatePure(gate.when, world: world, content: content) == true
    }

    public static func mode(_ content: ContentDB) -> TrialGateMode { content.trialGate?.mode ?? .fence }
    public static func heldStats(_ condition: Condition) -> Set<StatID> {
        switch condition {
        case .stat(let id, _, _): return [id]
        case .all(let xs), .any(let xs): return xs.reduce(into: []) { $0.formUnion(heldStats($1)) }
        case .not(let x): return heldStats(x)
        default: return []
        }
    }
}
