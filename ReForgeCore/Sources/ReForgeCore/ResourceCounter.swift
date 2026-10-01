/// 0...capacity の範囲に収まる資源カウンタ。
/// 増減は常に範囲内に丸め、実際に動いた量を返す(溢れた分・足りない分は捨てる)。
public struct ResourceCounter: Equatable, Hashable, Sendable {
    public private(set) var amount: Int
    public let capacity: Int

    public init(amount: Int = 0, capacity: Int) {
        precondition(capacity >= 0, "capacity は 0 以上")
        self.capacity = capacity
        self.amount = Self.clamp(amount, capacity: capacity)
    }

    public var isEmpty: Bool { amount == 0 }
    public var isFull: Bool { amount == capacity }

    /// delta だけ増減する(負なら減る)。範囲外は丸める。実際の変化量を返す。
    @discardableResult
    public mutating func adjust(by delta: Int) -> Int {
        let (sum, overflow) = amount.addingReportingOverflow(delta)
        let target = overflow ? (delta > 0 ? capacity : 0) : Self.clamp(sum, capacity: capacity)
        let applied = target - amount
        amount = target
        return applied
    }

    /// n (>= 0) だけ増やす。実際に増えた量を返す。
    @discardableResult
    public mutating func add(_ n: Int) -> Int {
        precondition(n >= 0, "add には 0 以上を渡す")
        return adjust(by: n)
    }

    /// n (>= 0) だけ減らす。実際に減った量(正の値)を返す。
    @discardableResult
    public mutating func consume(_ n: Int) -> Int {
        precondition(n >= 0, "consume には 0 以上を渡す")
        return -adjust(by: -n)
    }

    private static func clamp(_ value: Int, capacity: Int) -> Int {
        min(max(value, 0), capacity)
    }
}
