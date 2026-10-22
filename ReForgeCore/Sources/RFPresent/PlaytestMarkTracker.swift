import RFContent
import RFKernel
import RFRules
import RFWorld

/// 遊びの記録の節目の追跡(PT-B4)。まだ成り立っていない節目だけを評価し、初めて成り立った時刻を覚える。
/// WorldState と保存には入れない。アプリは記録の側に持ち、ボットは自分の中に持つ。
public struct PlaytestMarkTracker: Codable, Equatable, Sendable {
    /// 初めて成り立った時刻。
    public private(set) var reached: [String: GameTime] = [:]

    public init() {}

    /// 今回初めて成り立った節目の ID を、ID の順で返す。成り立った節目は二度と返さない。
    public mutating func update(_ w: WorldState, _ c: ContentDB) -> [String] {
        var fresh: [String] = []
        for (id, def) in c.playtestMarks.sorted(by: { $0.key < $1.key }) where reached[id] == nil {
            if ConditionEvaluator.evaluatePure(def.when, world: w, content: c) == true {
                reached[id] = w.clock.now
                fresh.append(id)
            }
        }
        return fresh
    }
}
