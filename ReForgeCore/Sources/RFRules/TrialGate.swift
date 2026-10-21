import RFContent
import RFKernel
import RFWorld

/// Rights are an execution environment, never saved with WorldState.
public struct Entitlements: Sendable, Equatable {
    public var fullGame: Bool
    public init(fullGame: Bool = true) { self.fullGame = fullGame }
}

public enum TrialGate {
    public static func closed(_ world: WorldState, _ content: ContentDB, _ entitlements: Entitlements) -> Bool {
        !entitlements.fullGame && content.trialGate.map {
            ConditionEvaluator.evaluatePure($0.when, world: world, content: content) == true
        } == true
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
