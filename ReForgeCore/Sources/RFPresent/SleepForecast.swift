import RFContent
import RFKernel
import RFRules
import RFSim
import RFWorld

/// 寝る見込みの 1 行の材料(W-11・W-02d)。写しに .time(.sleep) を当てた結果(Simulation.forecastSleep)から作る。
/// 別の式で見積もらない。Frame には入れない(1 夜ぶんを回すので毎フレームは重い。画面は日没の間、世界の版が変わったときに引く)。
public struct SleepForecast: Equatable, Sendable {
    public enum FireAtDawn: Equatable, Sendable { case holds, dies }
    public enum FurnaceAtDawn: Equatable, Sendable { case stays, cools }

    /// 今点いている焚き火が、寝た夜明けにまだ点いているか。点いていなければ nil。
    public var fire: FireAtDawn?
    /// 今熱い炉がある。夜明けに全部熱いままなら stays、1 つでも冷えれば cools。熱い炉が無ければ nil。
    public var furnace: FurnaceAtDawn?

    public var isEmpty: Bool { fire == nil && furnace == nil }

    public init(fire: FireAtDawn? = nil, furnace: FurnaceAtDawn? = nil) {
        self.fire = fire
        self.furnace = furnace
    }

    /// before(今の世界)と after(寝た夜明けの世界)から作る。
    public static func make(before: WorldState, after: WorldState, builder: FrameBuilder) -> SleepForecast {
        let content = builder.content
        var out = SleepForecast()
        if let pl = builder.primaryHearth(before), let s = Hearths.state(pl, content),
           let d = Hearths.def(pl, content), HearthRule.level(s, d) != .out {
            let kept = after.placements.items[pl.id].flatMap { p -> Bool? in
                guard Hearths.isCompleteForOutlook(p), let st = Hearths.state(p, content) else { return nil }
                return st.lit && st.fuel > 0
            } ?? false
            out.fire = kept ? .holds : .dies
        }
        var hotBefore: [EntityID] = []
        for id in before.placements.sortedIDs {
            guard let p = before.placements.items[id], FurnaceHeat.def(p, content) != nil,
                  FurnaceHeat.isHot(p, content) else { continue }
            hotBefore.append(id)
        }
        if !hotBefore.isEmpty {
            let stays = hotBefore.allSatisfy { id in
                after.placements.items[id].map { FurnaceHeat.isHot($0, content) } ?? false
            }
            out.furnace = stays ? .stays : .cools
        }
        return out
    }
}

extension GameHost {
    /// 日没・夜作業の間だけ。写しに .time(.sleep) を当てた結果から作る。昼は nil。世界・乱数・保存を進めない。
    public func sleepForecast() -> SleepForecast? {
        guard let f = simulation.forecastSleep(world) else { return nil }
        return SleepForecast.make(before: world, after: f.world, builder: builder)
    }
}
