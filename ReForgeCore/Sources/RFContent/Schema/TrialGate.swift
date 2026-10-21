import RFKernel

/// Data-defined boundary for a free opening.  Content normally omits this;
/// the public bundle must not choose either its position or its held items.
public struct TrialGateDef: Codable, Equatable, Sendable {
    public var when: Condition
    public var mode: TrialGateMode?
    public var holds: TrialHoldsDef?
    public var resume: TrialResume?
    public var onRelease: [Effect]?

    public init(when: Condition, mode: TrialGateMode? = nil, holds: TrialHoldsDef? = nil,
                resume: TrialResume? = nil, onRelease: [Effect]? = nil) {
        self.when = when; self.mode = mode; self.holds = holds; self.resume = resume; self.onRelease = onRelease
    }
}

public enum TrialGateMode: String, Codable, Equatable, Sendable { case fence, freeze }
public enum TrialResume: Codable, Equatable, Sendable { case judgeAtRelease, shiftThresholds }

public struct TrialHoldsDef: Codable, Equatable, Sendable {
    public var research: Bool?
    public var events: [EventID]?
    public var failures: [FailureRuleID]?
    public init(research: Bool? = nil, events: [EventID]? = nil, failures: [FailureRuleID]? = nil) {
        self.research = research; self.events = events; self.failures = failures
    }
}
