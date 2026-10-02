import RFContent
import RFKernel
import RFMap
import RFWorld

/// 火床の純粋な規則(序盤の設計 §3.2・W-02a)。焚き火(RFBase)と炉(RFProduction。U22)が同じ式を使う。持ち主: U21
///
/// 燃料はゲーム秒 × 1000 の整数。1 ゲーム秒ごとに「その秒の始めの段」で決まる率だけ減る。だから、
/// 何秒ずつ刻んで進めても(昼のリアルタイム・夜作業・寝るの一括)、入力が同じなら同じ燃料になる。
public enum HearthRule {
    public static let defaultStructurePermille = 100
    public static let defaultNightWorkPermille = 250
    public static let defaultBankedPermille = 333
    public static let defaultBankedLight = 1
    public static let defaultPileMax = 12
    public static let defaultTendBelowSeconds = 21_600

    /// 定義の初めの状態(建て終えたとき)。
    public static func initial(_ def: HearthDef) -> HearthState {
        let f = max(0, min(def.initialSeconds ?? 0, def.capSeconds)) * 1000
        return HearthState(fuel: f, lit: f > 0)
    }

    /// 段(消えていれば out)。
    public static func level(_ s: HearthState, _ def: HearthDef) -> HearthLevel {
        guard s.lit, s.fuel > 0 else { return .out }
        let n = def.thresholds.prefix(4).filter { s.fuel > $0 * 1000 }.count
        return HearthLevel(rawValue: max(1, n)) ?? .roaring
    }

    /// 灯りの半径。埋めてあれば bankedLight。
    public static func lightRadius(_ s: HearthState, _ def: HearthDef) -> Int {
        let l = level(s, def)
        guard l != .out else { return 0 }
        if s.banked { return def.bankedLight ?? defaultBankedLight }
        return def.light.indices.contains(l.rawValue) ? def.light[l.rawValue] : 0
    }

    /// 1 ゲーム秒あたりの減り(ゲーム秒 × 1000)。
    public static func rate(_ s: HearthState, _ def: HearthDef, structuresInLight: Int, nightWork: Bool) -> Int {
        let l = level(s, def)
        guard l != .out else { return 0 }
        let base = def.burnPermille.indices.contains(l.rawValue) ? def.burnPermille[l.rawValue] : 1000
        var r = base * (1000 + (def.structurePermille ?? defaultStructurePermille) * max(0, structuresInLight)) / 1000
        if nightWork { r += def.nightWorkPermille ?? defaultNightWorkPermille }
        if s.banked { r = r * (def.bankedPermille ?? defaultBankedPermille) / 1000 }
        return max(1, r)
    }

    /// 燃料 1 個で足される時間(ゲーム秒 × 1000)。燃料にならない物は nil。
    public static func fuelValue(_ item: ItemID, _ def: HearthDef) -> Int? {
        def.fuels[item].map { $0 * 1000 }
    }

    /// 点けるときの燃料(igniteSeconds に満たなければそこまで入れる)。
    public static func kindle(_ s: HearthState, _ def: HearthDef) -> HearthState {
        guard let k = def.igniteSeconds else { return s }
        var o = s
        o.fuel = max(o.fuel, min(k, def.capSeconds) * 1000)
        return o
    }

    /// 燃料を足す(上限で切る)。点いているかは変えない。
    public static func add(_ s: HearthState, _ def: HearthDef, item: ItemID, quantity: Int) -> HearthState? {
        guard let v = fuelValue(item, def), quantity > 0 else { return nil }
        var o = s
        o.fuel = min(def.capSeconds * 1000, o.fuel + v * quantity)
        return o
    }

    /// seconds ゲーム秒だけ燃やす。tended なら、燃料が tendBelowSeconds 以下になるたびに薪の山から 1 つくべる。
    /// 燃料が尽きたら消える(埋めた印も外れる)。
    public static func burn(_ s: HearthState, _ def: HearthDef, seconds: Int, structuresInLight: Int,
                            nightWork: Bool, tended: Bool) -> HearthState {
        var o = s
        var left = max(0, seconds)
        let tendAt = (def.tendBelowSeconds ?? defaultTendBelowSeconds) * 1000
        let pileValue = def.pileItem.flatMap { fuelValue($0, def) }
        while left > 0, o.lit, o.fuel > 0 {
            if tended, let pv = pileValue, o.pile > 0, o.fuel <= tendAt {
                o.pile -= 1
                o.fuel = min(def.capSeconds * 1000, o.fuel + pv)
                continue
            }
            let l = level(o, def)
            let r = rate(o, def, structuresInLight: structuresInLight, nightWork: nightWork)
            var bound = l.rawValue >= 1 && def.thresholds.indices.contains(l.rawValue - 1)
                ? def.thresholds[l.rawValue - 1] * 1000 : 0
            if tended, pileValue != nil, o.pile > 0, tendAt < o.fuel { bound = max(bound, tendAt) }
            let need = (o.fuel - bound + r - 1) / r
            let k = max(1, min(need, left))
            o.fuel -= k * r
            left -= k
        }
        if o.fuel <= 0 {
            o.fuel = 0
            o.lit = false
            o.banked = false
            o.litSinceDusk = false
        }
        return o
    }
}

/// 置いた火床の問い合わせと操作(世界を読む)。灯り・範囲の効果・provides の「燃えている間だけ」(W-02b・W-02c)もここ。
public enum Hearths {
    /// 置いた物の火床の定義(建造物・モジュール)。
    public static func def(_ p: Placement, _ content: ContentDB) -> HearthDef? {
        switch p.kind {
        case .structure(let k): content.structures[k]?.hearth
        case .module(let k): content.modules[k]?.hearth
        }
    }

    /// 置いた物の火床の状態(まだ持っていなければ定義の初め)。
    public static func state(_ p: Placement, _ content: ContentDB) -> HearthState? {
        guard let d = def(p, content) else { return nil }
        return (p.structure?.hearth ?? p.module?.hearth) ?? HearthRule.initial(d)
    }

    static func isComplete(_ p: Placement) -> Bool {
        if case .underConstruction = p.status { return false }
        return p.status != .broken
    }

    /// 置いた物の火床の段(火床でなければ nil。建造中・壊れていれば out)。
    public static func level(of p: Placement, _ content: ContentDB) -> HearthLevel? {
        guard let d = def(p, content), let s = state(p, content) else { return nil }
        return isComplete(p) ? HearthRule.level(s, d) : .out
    }

    /// 建造物の provides と auras が今効くか(StructureDef.whenLit)。火床でない物、whenLit の無い物は常に効く。
    public static func effectsActive(_ p: Placement, _ content: ContentDB) -> Bool {
        guard case .structure(let k) = p.kind, let need = content.structures[k]?.whenLit else { return true }
        guard let l = level(of: p, content) else { return true }
        return l >= need
    }

    /// 今効いている provides(燃えていなければ空。火床の light は段から読む)。
    public static func provides(_ p: Placement, _ content: ContentDB) -> [String: Int] {
        guard case .structure(let k) = p.kind, let sd = content.structures[k] else { return [:] }
        guard effectsActive(p, content) else { return [:] }
        var out = sd.provides
        if let d = sd.hearth, let s = state(p, content) {
            let r = isComplete(p) ? HearthRule.lightRadius(s, d) : 0
            if r > 0 { out["light"] = r } else { out["light"] = nil }
        }
        return out
    }

    /// 今の灯りの半径(建造物は火床の段か provides の light、モジュールは火床の段。熱い炉も灯りになる)。
    /// 炉の熱から半径を決める規則(1100℃ 以上で 3)は U22 がここに足す。
    public static func lightRadius(_ p: Placement, _ content: ContentDB) -> Int {
        switch p.kind {
        case .structure: return provides(p, content)["light"] ?? 0
        case .module:
            guard isComplete(p), let d = def(p, content), let s = state(p, content) else { return 0 }
            // 炉は熱で灯る(1100℃ 以上で半径 3。W-03)
            if let r = FurnaceHeat.lightRadius(p, content) { return r }
            return HearthRule.lightRadius(s, d)
        }
    }

    /// 番がいるか(生きていて地図にいる仲間が、この火床に付いている)。
    /// 番の正本は仲間の配属(火の番 Assignment.tendHearth は U22 が足す。それまでは .operate を番と見なす)。
    public static func isTended(_ id: EntityID, in w: WorldState) -> Bool {
        w.people.order.contains { pid in
            guard let ps = w.people[pid], ps.presence.isAlive, ps.position != nil else { return false }
            switch ps.override?.assignment ?? ps.assignment {
            case .tendHearth(let e) where e == id: return true
            case .operate(let e) where e == id: return true  // 火の番の配属が入る前の形(古い保存)
            default: return false
            }
        }
    }

    /// 火の灯りの中にある、ほかの完成した建造物の数(燃える速さに掛かる)。
    public static func structuresInLight(_ id: EntityID, in w: WorldState, content: ContentDB) -> Int {
        guard let p = w.placements.items[id] else { return 0 }
        let r = lightRadius(p, content)
        guard r > 0 else { return 0 }
        return w.placements.sortedIDs.filter { oid in
            guard oid != id, let o = w.placements.items[oid], case .structure = o.kind, isComplete(o),
                  o.at.layer == p.at.layer else { return false }
            return VisionRule.inCircle(o.at.point, center: p.at.point, radius: r)
        }.count
    }

    /// その火の灯りで夜作業をしているか(夜作業の相で、ノアが灯りの中にいる)。
    public static func nightWork(_ id: EntityID, in w: WorldState, content: ContentDB) -> Bool {
        guard w.clock.phase == .nightWork, !w.clock.sleeping, let p = w.placements.items[id],
              let pos = w.people[.noah]?.position, pos.layer == p.at.layer else { return false }
        let r = lightRadius(p, content)
        return r > 0 && VisionRule.inCircle(pos.point, center: p.at.point, radius: r)
    }

    /// その場所が、どれかの建造物の灯りの中か。
    public static func isLit(_ pos: WorldPoint, in w: WorldState, content: ContentDB) -> Bool {
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], p.at.layer == pos.layer, isComplete(p) else { continue }
            let r = lightRadius(p, content)
            if r > 0, VisionRule.inCircle(pos.point, center: p.at.point, radius: r) { return true }
        }
        return false
    }

    /// 火床を持つ建造物(ID 順)。
    public static func structureHearths(_ w: WorldState, _ content: ContentDB) -> [EntityID] {
        w.placements.sortedIDs.filter { id in
            guard let p = w.placements.items[id], case .structure(let k) = p.kind else { return false }
            return content.structures[k]?.hearth != nil
        }
    }

    /// 拠点の焚き火のうち最も強い段(火床が無ければ out)。働ける人数の火の枠(INV-O10)などが読む。
    public static func campfireLevel(_ w: WorldState, _ content: ContentDB) -> HearthLevel {
        structureHearths(w, content).compactMap { w.placements.items[$0].flatMap { level(of: $0, content) } }.max() ?? .out
    }

    /// 場所に最も近い火床(同じ層。距離が同じなら ID の小さい方)。
    public static func nearest(to at: WorldPoint, in w: WorldState, content: ContentDB) -> EntityID? {
        var best: (Int, EntityID)?
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], p.at.layer == at.layer, def(p, content) != nil, isComplete(p) else { continue }
            let d = p.footprint.map { GridPoint(p.at.point.x + $0.x, p.at.point.y + $0.y).chebyshev(to: at.point) }.min() ?? 0
            if best == nil || d < best!.0 { best = (d, id) }
        }
        return best?.1
    }

    // MARK: 書く

    /// 火床の状態を書き戻す(段が変われば出来事を出す)。
    public static func write(_ id: EntityID, _ s: HearthState, _ ctx: inout StepContext) {
        guard let p = ctx.world.placements.items[id], let d = def(p, ctx.content) else { return }
        let before = level(of: p, ctx.content) ?? .out
        let old = state(p, ctx.content)
        if old == s, p.structure?.hearth != nil || p.module?.hearth != nil { return }
        switch p.kind {
        case .structure:
            var rt = p.structure ?? StructureRuntime()
            rt.hearth = s
            ctx.world.placements.items[id]?.structure = rt
        case .module:
            ctx.world.placements.items[id]?.module?.hearth = s
        }
        let after = isComplete(p) ? HearthRule.level(s, d) : .out
        if after != before || HearthRule.lightRadius(old ?? s, d) != HearthRule.lightRadius(s, d) {
            ctx.changes.mark(.placements)
            ctx.changes.markTile(p.at, .placements)
        }
        if after != before { ctx.emit(.hearthLevelChanged(placement: id, level: after)) }
    }

    /// 効果から(内容の「くべる」「火を起こす」「火を埋める」)。
    public static func applyEffect(_ op: HearthEffectOp, to id: EntityID, _ ctx: inout StepContext) {
        guard let p = ctx.world.placements.items[id], let d = def(p, ctx.content), var s = state(p, ctx.content) else { return }
        switch op {
        case .addFuel(let item, let n):
            guard let o = HearthRule.add(s, d, item: item, quantity: n) else {
                ctx.warnings.append("火床の燃料にならない: \(item)")
                return
            }
            s = o
        case .ignite(let chance, let skill, let skillChance):
            if var p = chance {
                if let sk = skill, let sc = skillChance, let actor = ctx.cause.flatMap({ ctx.world.ledger.record($0)?.actor }),
                   ctx.world.people[actor]?.skills.contains(sk) == true { p = sc }
                let roll = ctx.random("hearth") { $0.int(below: 1000) }
                guard roll < p else { return }
            }
            s = HearthRule.kindle(s, d)
            guard s.fuel > 0 else { return }
            s.lit = true
            s.banked = false
        case .bank:
            guard s.lit else { return }
            s.banked = true
        }
        write(id, s, &ctx)
    }

    /// 1 ステップ燃やす(建造物の火床。モジュールの炉は RFProduction が同じ HearthRule で燃やす)。
    public static func advanceStructures(seconds: Int, _ ctx: inout StepContext) {
        for id in structureHearths(ctx.world, ctx.content) {
            guard let p = ctx.world.placements.items[id], isComplete(p), let d = def(p, ctx.content),
                  let s = state(p, ctx.content) else { continue }
            if !s.lit, p.structure?.hearth != nil { continue }
            let n = structuresInLight(id, in: ctx.world, content: ctx.content)
            let nw = nightWork(id, in: ctx.world, content: ctx.content)
            let o = HearthRule.burn(s, d, seconds: seconds, structuresInLight: n, nightWork: nw,
                                    tended: isTended(id, in: ctx.world))
            write(id, o, &ctx)
        }
    }

    /// 日没: いま点いている火床に「日没から消えていない」の印を付ける。
    public static func markDusk(_ ctx: inout StepContext) {
        for id in structureHearths(ctx.world, ctx.content) {
            guard let p = ctx.world.placements.items[id], var s = state(p, ctx.content) else { continue }
            s.litSinceDusk = s.lit && s.fuel > 0 && isComplete(p)
            write(id, s, &ctx)
        }
    }

    /// 夜明け: 日没から消えなかった火床があれば、定義の夜の数を 1 足す(埋み火の夜も数える。カウンタごとに 1 夜 1 回)。
    public static func countDawn(_ ctx: inout StepContext) {
        var counted = Set<CounterID>()
        for id in structureHearths(ctx.world, ctx.content) {
            guard let p = ctx.world.placements.items[id], let d = def(p, ctx.content), var s = state(p, ctx.content)
            else { continue }
            if s.litSinceDusk, s.lit, let c = d.nightsCounter, !counted.contains(c) {
                counted.insert(c)
                ctx.world.narrative.counters[c, default: 0] += 1
                ctx.changes.mark(.narrative)
            }
            s.litSinceDusk = false
            write(id, s, &ctx)
        }
    }
}
