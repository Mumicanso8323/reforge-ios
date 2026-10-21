import RFKernel

/// Saved progress of a data-defined free-opening boundary.  Entitlements are
/// intentionally not part of this state: a save is portable between devices.
public struct TrialState: Codable, Equatable, Sendable {
    public var deferred: [TrialHeld] = []
    public var noticed: Bool?
    public var releasedAt: GameTime?
    public var cutStats: [StatID: Int]?
    public var shifts: [FailureRuleID: [StatID: Int]]?
    public init() {}
}

public struct TrialHeld: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case event, failure }
    public var kind: Kind
    public var id: String
    public var since: GameTime
    public var stats: [StatID: Int]?
    public init(kind: Kind, id: String, since: GameTime, stats: [StatID: Int]? = nil) {
        self.kind = kind; self.id = id; self.since = since; self.stats = stats
    }
}
