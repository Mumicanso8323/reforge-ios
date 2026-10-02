import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 新しい世界を作る(コンテンツの StartDef と、地図の生成)。
/// 地図の生成は RFMap の担当の実装(MapGenerating)を渡す。テストは RFTestSupport の平らな地図を渡す。
public struct WorldFactory: Sendable {
    public let content: ContentDB
    public let mapGenerator: any MapGenerating

    public init(content: ContentDB, mapGenerator: any MapGenerating) {
        self.content = content
        self.mapGenerator = mapGenerator
    }

    public func newWorld(seed: UInt64) -> WorldState {
        var streams = RandomStreams(seed: seed)
        var ids = IDAllocator()
        let map = streams.use(.mapgen) { rng in
            mapGenerator.generate(config: content.mapGen, terrains: content.terrains, rng: &rng,
                                  allocate: { EntityID(ids.next()) })
        }
        var w = WorldState(seed: seed, map: map)
        w.rng = streams
        w.ids = ids
        w.base.area = map.baseArea
        for (id, def) in content.stats { w.survival.stats[id] = Milli(raw: Int64(def.initial)) }

        for (id, g) in content.groups {
            var gs = GroupState()
            gs.relation = g.relation ?? 0
            gs.flags = Set(g.flags ?? [])
            w.people.groups[id] = gs
        }

        if let sc = content.start.clock {
            let dayLen = content.clock.dayGameSeconds
            if let d = sc.day { w.clock.day = d }
            if let h = sc.hoursBeforeDusk {
                let before = min(max(0, Int64(h) * 3600), dayLen)
                // 夜明けを 0 に置き、日没の h 時間前から始める(GameTime を負にしない)
                w.clock.now = GameTime(seconds: dayLen - before)
            }
            w.clock.held = sc.held ?? false
        }

        var ctx = StepContext(world: w, content: content)
        let s = content.start
        for p in s.members {
            var ps = PersonState(id: p, presence: .member(since: .zero))
            ps.position = map.spawn
            ps.ideology = content.people[p]?.ideology ?? [:]
            ps.group = content.people[p]?.group
            ctx.world.people[p] = ps
        }
        for p in s.unmet ?? [] {
            var ps = PersonState(id: p, presence: .unmet)
            ps.group = content.people[p]?.group
            ctx.world.people[p] = ps
        }
        for y in s.items {
            let stuff: Stuff? = y.matter.map { .matter($0) } ?? y.item.map { .item($0) }
            if let stuff { ctx.addStock(stuff, y.min, to: .base) }
        }
        for f in s.facts { ctx.learn(f) }
        EffectApplier.apply(s.unlocks.map { .unlock(target: $0) }, &ctx, cause: nil)
        for o in s.objectives ?? [] { ctx.world.narrative.objectives[o] = .active }
        ctx.world.narrative.chapter = s.chapter
        for e in s.events ?? [] { ctx.world.narrative.scheduled.append(ScheduledEvent(event: e, at: .zero)) }
        _ = ctx.drainEvents()
        return ctx.world
    }
}
