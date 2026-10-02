import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 経路を引く・歩かせる(RFMap の Pathfinder を使う)。
///
/// - 既知は `knowledge.mapKnown`(一員で共有。人ごとの `personalKnown` があればそちら)。巻き戻しをまたいで残る。
///   地図の層が持つ視界(MapLayer.visibility)は使わない(地図の切れ端は巻き戻しで戻るため)。
/// - 霧の先(まだ見ていないマス)は平地と仮定して通る(PathOptions.tap と同じ考え)。歩いて霧が晴れたら引き直す。
/// - 置いたモジュールのマスは通れない(行き先がそのマスなら隣まで)。
/// - 1 ステップの中で何人ぶんも探すので、作業領域(PathWorkspace)を使い回す。
struct PathPlanner {
    let world: WorldState
    let content: ContentDB
    let costs: MoveCostTable
    let workspace: PathWorkspace
    /// 層ごとの通れないマス(モジュール)。
    private var blockedCache: [LayerID: Set<GridPoint>] = [:]

    init(world: WorldState, content: ContentDB, workspace: PathWorkspace) {
        self.world = world
        self.content = content
        self.costs = MoveCostTable(terrains: content.terrains)
        self.workspace = workspace
    }

    mutating func blocked(_ layer: LayerID) -> Set<GridPoint> {
        if let b = blockedCache[layer] { return b }
        var s = Set<GridPoint>()
        for id in world.placements.sortedIDs {
            guard let p = world.placements.items[id], p.at.layer == layer, case .module = p.kind else { continue }
            for o in p.footprint { s.insert(p.at.point + o) }
        }
        blockedCache[layer] = s
        return s
    }

    func known(_ person: PersonID, _ layer: LayerID) -> GridBitset? {
        world.people[person]?.personalKnown?[layer] ?? world.knowledge.mapKnown[layer]
    }

    /// 記録済みの地形で通れるマスか(霧は見ない)。
    mutating func passableTruth(_ p: GridPoint, _ layer: LayerID) -> Bool {
        guard let l = world.map[layer], let b = l.biome(at: p), costs.cost(b) != nil else { return false }
        return !blocked(layer).contains(p)
    }

    /// 隣のマスへ入る移動コスト(千分の一の体力。斜めは 1.4 倍。通れなければ 0)。
    func enterCost(from a: GridPoint, to b: GridPoint, _ layer: LayerID) -> Int {
        guard let biome = world.map[layer]?.biome(at: b) else { return 0 }
        let diagonal = a.x != b.x && a.y != b.y
        return (diagonal ? costs.diagonalCost(biome) : costs.cost(biome)) ?? 0
    }

    /// 人が知っている範囲で通れると思えるマスか(未知は通れると仮定)。
    mutating func passableBelief(_ p: GridPoint, _ layer: LayerID, known: GridBitset?) -> Bool {
        guard let l = world.map[layer], l.size.contains(p) else { return false }
        if blocked(layer).contains(p) { return false }
        if known?[p] != true { return true }
        guard let b = l.biome(at: p) else { return false }
        return costs.cost(b) != nil
    }

    /// from → goal の経路(出発点を含まず、行き先を含む)。届かなければ nil。
    mutating func route(for person: PersonID, layer: LayerID, from: GridPoint, to goal: GridPoint,
                        allowGoal: Bool = false) -> (path: [GridPoint], throughFog: Bool)? {
        guard let l = world.map[layer] else { return nil }
        let k = known(person, layer)
        var block = blocked(layer)
        if allowGoal { block.remove(goal) }
        block.remove(from)
        let terrain = l.terrain
        let outcome = Pathfinder.route(size: l.size, from: from, to: goal, costs: costs, options: .tap,
                                       workspace: workspace) { p in
            if block.contains(p) { return .impassable }
            if k?[p] != true { return .assumed(.plain) }
            guard let b = terrain.biome(at: p) else { return .impassable }
            return .known(b)
        }
        switch outcome {
        case .known(let m): return (m.steps, false)
        case .throughFog(let m, _): return (m.steps, true)
        case .blocked: return nil
        }
    }

    /// 対象(マスの集まり)のそばへ行く経路。対象のマスに立てる(通れる)ならそこへ、立てなければ隣の 8 マスのうち
    /// 一番近く着けるところへ。既にそばにいれば空の経路。届かなければ nil。
    mutating func approach(for person: PersonID, layer: LayerID, from: GridPoint, target: [GridPoint],
                           standOn: Bool) -> (path: [GridPoint], throughFog: Bool, goal: GridPoint)? {
        let k = known(person, layer)
        if standOn, target.contains(from) { return ([], false, from) }
        if !standOn, target.contains(where: { $0.chebyshev(to: from) <= 1 }), !target.contains(from) {
            return ([], false, from)
        }
        var best: (path: [GridPoint], throughFog: Bool, goal: GridPoint, cost: Int)?
        var candidates: [GridPoint] = []
        if standOn {
            candidates = target.filter { passableBelief($0, layer, known: k) }
        }
        if candidates.isEmpty {
            var seen = Set(target)
            for t in target {
                for n in t.neighbors8 where !seen.contains(n) {
                    seen.insert(n)
                    if passableBelief(n, layer, known: k) { candidates.append(n) }
                }
            }
        }
        // 近い順に(同じなら座標順)。最初に届いた 3 つの中で一番短いものを使う(全部は探さない)
        candidates.sort { ($0.chebyshev(to: from), $0) < ($1.chebyshev(to: from), $1) }
        var tried = 0
        for c in candidates {
            if c == from { return ([], false, from) }
            guard let r = route(for: person, layer: layer, from: from, to: c) else { continue }
            if best == nil || r.path.count < best!.cost { best = (r.path, r.throughFog, c, r.path.count) }
            tried += 1
            if tried >= 3 { break }
        }
        return best.map { ($0.path, $0.throughFog, $0.goal) }
    }
}

/// 歩く(1 ステップぶん進める)。
enum Walking {
    /// 4 方向の向き(斜めは横の向きを優先)。
    static func facing(from a: GridPoint, to b: GridPoint, current: Direction) -> Direction {
        let dx = b.x - a.x, dy = b.y - a.y
        if dx == 0 && dy == 0 { return current }
        if abs(dx) >= abs(dy) { return dx > 0 ? .east : .west }
        return dy > 0 ? .south : .north
    }

    /// 人を 1 ステップぶん歩かせる。着いたら arrived を出す。次のマスが塞がっていたら引き直す。
    static func advance(_ id: PersonID, speed: Int, _ ctx: inout StepContext, planner: inout PathPlanner) {
        guard var ps = ctx.world.people[id], var m = ps.motion, let pos = ps.position else { return }
        m.progress += speed
        var here = pos
        var replan = false
        var tiles = 0
        var cost = 0
        while m.progress >= 1000, let next = m.path.first {
            if !planner.passableTruth(next, here.layer) {
                // 着いてみたら通れない(霧の先が水だった・その間にモジュールが置かれた)
                m.progress = 0
                replan = true
                break
            }
            m.path.removeFirst()
            m.progress -= 1000
            tiles += 1
            cost += planner.enterCost(from: here.point, to: next, here.layer)
            ps.facing = facing(from: here.point, to: next, current: ps.facing)
            here = WorldPoint(here.layer, next)
        }
        ps.position = here
        if here != pos { ctx.changes.mark(.people) }
        if tiles > 0 { ctx.emit(.walked(person: id, tiles: tiles, staminaCost: cost)) }
        if m.path.isEmpty && !replan {
            ps.motion = nil
            ctx.world.people[id] = ps
            ctx.emit(.arrived(person: id, at: here))
            return
        }
        ps.motion = m
        ctx.world.people[id] = ps
        if replan { _ = Walking.replan(id, &ctx, planner: &planner) }
    }

    /// 行き先はそのままに、経路を引き直す(霧が晴れた・塞がれた)。届かなくなったら止まる。
    @discardableResult
    static func replan(_ id: PersonID, _ ctx: inout StepContext, planner: inout PathPlanner) -> Bool {
        guard var ps = ctx.world.people[id], let m = ps.motion, let pos = ps.position else { return false }
        let goal = m.goal ?? m.path.last ?? pos.point
        // 次のマスへの途中なら、そのマスから引く(見た目が戻らないように)。通れなくなっていたら今のマスから
        var anchor = pos.point
        var prefix: [GridPoint] = []
        var progress = 0
        if m.progress > 0, let next = m.path.first, planner.passableTruth(next, pos.layer) {
            anchor = next
            prefix = [next]
            progress = m.progress
        }
        guard let r = planner.route(for: id, layer: pos.layer, from: anchor, to: goal) else {
            ps.motion = nil
            ps.activity = .idle
            ctx.world.people[id] = ps
            ctx.changes.mark(.people)
            return false
        }
        let path = prefix + r.path
        ps.motion = path.isEmpty ? nil : Motion(path: path, progress: progress, goal: goal, throughFog: r.throughFog)
        ctx.world.people[id] = ps
        ctx.changes.mark(.people)
        return true
    }

    /// 新しい経路を引く起点: 次のマスへの途中ならそのマス(見た目が戻らないように)、そうでなければ今のマス。
    static func anchor(_ ps: PersonState, planner: inout PathPlanner) -> GridPoint? {
        guard let pos = ps.position else { return nil }
        if let m = ps.motion, m.progress > 0, let next = m.path.first, planner.passableTruth(next, pos.layer) { return next }
        return pos.point
    }

    /// 経路を付けて歩き出す。anchor(Walking.anchor)が今のマスでなければ、そのマスへの進みを保って経由する。
    static func start(_ id: PersonID, anchor: GridPoint, path: [GridPoint], goal: GridPoint, throughFog: Bool,
                      _ ctx: inout StepContext) {
        guard var ps = ctx.world.people[id], let pos = ps.position else { return }
        var progress = 0
        var p = path
        if anchor != pos.point {
            progress = ps.motion?.progress ?? 0
            p = [anchor] + p
        }
        ps.motion = p.isEmpty ? nil : Motion(path: p, progress: progress, goal: goal, throughFog: throughFog)
        ctx.world.people[id] = ps
        ctx.changes.mark(.people)
    }
}
