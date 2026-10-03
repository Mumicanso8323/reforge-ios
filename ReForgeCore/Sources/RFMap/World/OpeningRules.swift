import RFKernel

/// 序盤の時間の予算を、どの seed でも成り立たせる地図の保証(序盤の設計 v0.4 の W-12・TEST-O12)。
///
/// - 地形で決まるもの(残り火のそばの森・拠点の近くの森・川岸と露頭へ歩く歩数・露頭のそばの森の縁)は、
///   足りない森を補ってから、目印の検証(verify)の作り直しの輪で確かめる。満たさない案は捨てて次の案を引く(決定的)。
/// - 鉱脈(岩山の 2 つ目の鉄と採掘回数の合計・石炭の鉱脈)と獣の巣は、確定の鉱脈を置いた直後に足して必ず満たす。
///   置く場所は乱数を使わずに決め、鉱脈の組成だけを SeededRandom.derived(seed, 104) で作る(103 は岩山の奥の鉱脈 U19)。
///
/// 数はどれも整数(保存に小数を入れない)。距離は 96×96 の地図を基準にし、小さい地図では目印と同じく縮める。
/// 値は R1 の仮値。コンテンツの地図の設定 `opening` で上書きできる。
public struct OpeningRules: Codable, Equatable, Sendable {
    /// 残り火(自分たちの残骸)の占めるマスからのチェビシェフ距離。この内側の森のマスを数える。
    public var emberForestRadius: Int
    /// その森のマスの下限。
    public var emberForestMin: Int
    /// 拠点の整地からのチェビシェフ距離(BaseArea.ringDistance)。この内側の森のマスを数える。
    public var forestRing: Int
    /// その森のマスの下限(枝の 5 日の循環 63 と伐る 15。§2.6.8)。
    public var forestMin: Int
    /// 拠点の中心 → 川岸の土石(粘土)の最安経路の歩数の上限(1 日目に水と粘土に届く)。
    public var clayBankSteps: Int
    /// 拠点の中心 → 露頭の最安経路の歩数の上限(2 日目の昼に往復できる)。
    public var outcropSteps: Int
    /// 露頭からこの距離(ユークリッド)の内側に森のマスがある(3 日目の最初の伐採と窯の置き場)。
    public var outcropForestEdge: Int
    /// 岩山の 2 つ目の鉄の鉱脈を置く、露頭からの距離の幅(最初は見つかっていない)。
    public var secondIronMin: Int
    public var secondIronMax: Int
    /// 露頭と 2 つ目の鉄の採掘回数の合計の下限(足りなければ 2 つ目の回数を足す)。
    public var ironExtractionsMin: Int
    /// 石炭の鉱脈を置く、露頭からの距離の幅(P-09)。
    public var coalFromOutcropMin: Int
    public var coalFromOutcropMax: Int
    /// 獣の巣を置く、露頭からの距離の幅(森の中。W-02c の縄張り)。
    public var nestFromOutcropMin: Int
    public var nestFromOutcropMax: Int
    /// 自分たちの残骸(wreck.home)からこのチェビシェフ距離の内側に、焚き火台を置ける乾いた空きマスを 1 つ以上残す
    /// (最初の「火を起こす」の placeStructure は残骸のそばの 0〜3 マスを探す。U21 の StructureSites.spot)。nil なら 3。
    public var firstFireRadius: Int?
    /// ノアの始まりのマスの隣 8 マスの森の下限(W-23。生成で足りなければ乾いた陸を森にする)。既定 1。
    public var startReachForestMin: Int
    /// 最初の火の置き場から半径 2(チェビシェフ)の森の下限(W-23)。既定 2。
    public var firstLightForestMin: Int
    /// 最初の夜の灯りの半径(火床の最大の段。夜明けに初めて見える置き場はこの外に置く。W-23 SL-16)。既定 5。
    public var firstNightLightRadius: Int

    private enum CodingKeys: String, CodingKey {
        case emberForestRadius, emberForestMin, forestRing, forestMin, clayBankSteps, outcropSteps, outcropForestEdge
        case secondIronMin, secondIronMax, ironExtractionsMin, coalFromOutcropMin, coalFromOutcropMax
        case nestFromOutcropMin, nestFromOutcropMax, firstFireRadius
        case startReachForestMin, firstLightForestMin, firstNightLightRadius
    }

    /// 古い保存・古い設定は新しい欄を持たない。無ければ既定で読む。
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        emberForestRadius = try c.decode(Int.self, forKey: .emberForestRadius)
        emberForestMin = try c.decode(Int.self, forKey: .emberForestMin)
        forestRing = try c.decode(Int.self, forKey: .forestRing)
        forestMin = try c.decode(Int.self, forKey: .forestMin)
        clayBankSteps = try c.decode(Int.self, forKey: .clayBankSteps)
        outcropSteps = try c.decode(Int.self, forKey: .outcropSteps)
        outcropForestEdge = try c.decode(Int.self, forKey: .outcropForestEdge)
        secondIronMin = try c.decode(Int.self, forKey: .secondIronMin)
        secondIronMax = try c.decode(Int.self, forKey: .secondIronMax)
        ironExtractionsMin = try c.decode(Int.self, forKey: .ironExtractionsMin)
        coalFromOutcropMin = try c.decode(Int.self, forKey: .coalFromOutcropMin)
        coalFromOutcropMax = try c.decode(Int.self, forKey: .coalFromOutcropMax)
        nestFromOutcropMin = try c.decode(Int.self, forKey: .nestFromOutcropMin)
        nestFromOutcropMax = try c.decode(Int.self, forKey: .nestFromOutcropMax)
        firstFireRadius = try c.decodeIfPresent(Int.self, forKey: .firstFireRadius)
        startReachForestMin = try c.decodeIfPresent(Int.self, forKey: .startReachForestMin) ?? 1
        firstLightForestMin = try c.decodeIfPresent(Int.self, forKey: .firstLightForestMin) ?? 2
        firstNightLightRadius = try c.decodeIfPresent(Int.self, forKey: .firstNightLightRadius) ?? 5
    }

    public init(emberForestRadius: Int, emberForestMin: Int, forestRing: Int, forestMin: Int, clayBankSteps: Int,
                outcropSteps: Int, outcropForestEdge: Int, secondIronMin: Int, secondIronMax: Int,
                ironExtractionsMin: Int, coalFromOutcropMin: Int, coalFromOutcropMax: Int,
                nestFromOutcropMin: Int, nestFromOutcropMax: Int,
                startReachForestMin: Int = 1, firstLightForestMin: Int = 2, firstNightLightRadius: Int = 5) {
        self.startReachForestMin = startReachForestMin
        self.firstLightForestMin = firstLightForestMin
        self.firstNightLightRadius = firstNightLightRadius
        self.emberForestRadius = emberForestRadius
        self.emberForestMin = emberForestMin
        self.forestRing = forestRing
        self.forestMin = forestMin
        self.clayBankSteps = clayBankSteps
        self.outcropSteps = outcropSteps
        self.outcropForestEdge = outcropForestEdge
        self.secondIronMin = secondIronMin
        self.secondIronMax = secondIronMax
        self.ironExtractionsMin = ironExtractionsMin
        self.coalFromOutcropMin = coalFromOutcropMin
        self.coalFromOutcropMax = coalFromOutcropMax
        self.nestFromOutcropMin = nestFromOutcropMin
        self.nestFromOutcropMax = nestFromOutcropMax
    }

    /// R1(96×96)の仮値(序盤の設計 v0.4 の W-12)。
    public static let r1 = OpeningRules(
        emberForestRadius: 3, emberForestMin: 6,
        forestRing: 8, forestMin: 70,
        clayBankSteps: 20, outcropSteps: 40, outcropForestEdge: 8,
        secondIronMin: 6, secondIronMax: 12, ironExtractionsMin: 120,
        coalFromOutcropMin: 12, coalFromOutcropMax: 20,
        nestFromOutcropMin: 10, nestFromOutcropMax: 15
    )

    /// 短い辺が 96 より小さい地図に合わせて、遠くの距離を縮める(拠点のまわりと数は縮めない)。
    public func scaled(to size: MapSize) -> OpeningRules {
        let k = min(1, Double(min(size.width, size.height)) / 96)
        guard k < 1 else { return self }
        func s(_ v: Int) -> Int { max(1, Int((Double(v) * k).rounded())) }
        var r = self
        r.outcropSteps = s(outcropSteps)
        r.secondIronMin = s(secondIronMin)
        r.secondIronMax = max(r.secondIronMin + 2, s(secondIronMax))
        r.coalFromOutcropMin = s(coalFromOutcropMin)
        r.coalFromOutcropMax = max(r.coalFromOutcropMin + 2, s(coalFromOutcropMax))
        r.nestFromOutcropMin = s(nestFromOutcropMin)
        r.nestFromOutcropMax = max(r.nestFromOutcropMin + 2, s(nestFromOutcropMax))
        return r
    }
}

extension DepositID {
    /// 岩山の裏の石炭の鉱脈(P-09)。
    public static let coal = DepositID("deposit.coal")
    /// 岩山の 2 つ目の鉄の鉱脈(露頭から 6〜12 マス。最初は見つかっていない)。
    public static let secondIron = DepositID("deposit.mountain.iron")
}

extension PlacementID {
    /// 序盤の獣の巣(露頭から 10〜15 マスの森の中)。
    public static let openingNest = PlacementID("nest.opening")
}

/// 序盤の保証の測り方と、足し方。
public enum OpeningGuarantee {
    /// 獣の巣の型(POICatalog の wolf_nest)。
    static let nestTemplate = POITemplateID("wolf_nest")

    /// 残り火(自分たちの残骸)の占めるマス。拠点の中央 3×2(WorldMapGenerator.placeFixedContent と同じ)。
    public static func emberCells(_ base: BaseArea) -> [GridPoint] {
        let a = base.center - GridPoint(1, 1)
        return [GridPoint(0, 0), GridPoint(1, 0), GridPoint(2, 0), GridPoint(0, 1), GridPoint(1, 1), GridPoint(2, 1)]
            .map { a + $0 }
    }

    static func emberDistance(_ p: GridPoint, _ base: BaseArea) -> Int {
        emberCells(base).map { $0.chebyshev(to: p) }.min() ?? Int.max
    }

    /// 残り火のそばの森のマスの数。
    public static func emberForest(_ t: TerrainGrid, base: BaseArea, radius: Int) -> Int {
        var n = 0
        let c = base.center
        for y in (c.y - radius - 1)...(c.y + radius + 1) {
            for x in (c.x - radius - 2)...(c.x + radius + 2) {
                let p = GridPoint(x, y)
                if t.biome(at: p) == .forest, emberDistance(p, base) <= radius { n += 1 }
            }
        }
        return n
    }

    /// 拠点の整地から ring 以内(整地の外)の森のマスの数。
    public static func forestNearBase(_ t: TerrainGrid, base: BaseArea, ring: Int) -> Int {
        ringCells(base, ring).filter { t.biome(at: $0) == .forest }.count
    }

    static func ringCells(_ base: BaseArea, _ ring: Int) -> [GridPoint] {
        var out: [GridPoint] = []
        for y in (base.minCorner.y - ring)...(base.maxCorner.y + ring) {
            for x in (base.minCorner.x - ring)...(base.maxCorner.x + ring) {
                let p = GridPoint(x, y)
                if !base.contains(p) { out.append(p) }
            }
        }
        return out
    }

    /// 足りない森を補う(乱数は使わない)。
    /// 1. 残り火のそば: 整地の外で残り火から radius 以内の乾いた陸(草地・整地)を森にする。
    /// 2. 拠点の近く: 森が下限に届くまで、既にある森に隣り合う草地を、整地に近い順に森にする(森が育つ形)。
    static func stampForests(_ t: inout TerrainGrid, base: BaseArea, rules: OpeningRules) {
        if rules.emberForestMin > 0 {
            let r = rules.emberForestRadius
            let c = base.center
            for y in (c.y - r - 1)...(c.y + r + 1) {
                for x in (c.x - r - 2)...(c.x + r + 2) {
                    let p = GridPoint(x, y)
                    guard !base.contains(p), emberDistance(p, base) <= r, let b = t.biome(at: p) else { continue }
                    if b == .plain || b == .cleared { t.set(p, .forest) }
                }
            }
        }
        let ring = ringCells(base, rules.forestRing).filter { t.size.contains($0) }
        var count = ring.filter { t.biome(at: $0) == .forest }.count
        guard count < rules.forestMin else { return }
        // 残り火のそばの林(整地の北のふち)から塊で育てる。整地を森で囲まない(森を避けて出る道を残す)
        let anchor = GridPoint(base.center.x, base.minCorner.y - 1 - rules.forestRing / 2)
        var open = Set(ring.filter { t.biome(at: $0) == .plain || t.biome(at: $0) == .cleared })
        while count < rules.forestMin {
            let grow = open.filter { p in p.neighbors8.contains { t.biome(at: $0) == .forest } }
            let pool = grow.isEmpty ? open : grow
            guard let p = pool.min(by: { ($0.distanceSquared(to: anchor), $0) < ($1.distanceSquared(to: anchor), $1) })
            else { break }
            t.set(p, .forest)
            open.remove(p)
            count += 1
        }
    }

    /// 最安経路の歩数(届かなければ Int.max)。
    static func steps(_ t: TerrainGrid, from: GridPoint, to: GridPoint, workspace ws: PathWorkspace) -> Int {
        guard let p = Pathfinder.findPath(size: t.size, from: from, to: to, workspace: ws, biomeAt: { t.biome(at: $0) })
        else { return Int.max }
        return p.steps.count
    }

    static func hasForest(near p: GridPoint, within r: Int, _ t: TerrainGrid) -> Bool {
        for y in (p.y - r)...(p.y + r) {
            for x in (p.x - r)...(p.x + r) {
                let q = GridPoint(x, y)
                if q.distanceSquared(to: p) <= r * r, t.biome(at: q) == .forest { return true }
            }
        }
        return false
    }

    /// 地形で決まる保証(目印の検証の一部)。
    static func verifyTerrain(_ lm: Landmarks, terrain t: TerrainGrid, rules r: OpeningRules, workspace ws: PathWorkspace) -> Bool {
        guard emberForest(t, base: lm.base, radius: r.emberForestRadius) >= r.emberForestMin else { return false }
        guard forestNearBase(t, base: lm.base, ring: r.forestRing) >= r.forestMin else { return false }
        guard hasForest(near: lm.outcrop, within: r.outcropForestEdge, t) else { return false }
        guard steps(t, from: lm.base.center, to: lm.clayBank, workspace: ws) <= r.clayBankSteps else { return false }
        return steps(t, from: lm.base.center, to: lm.outcrop, workspace: ws) <= r.outcropSteps
    }

    // MARK: 鉱脈と巣

    /// 岩山の 2 つ目の鉄(と採掘回数の合計)・石炭の鉱脈・獣の巣を置く。
    static func placeFixed(_ layer: inout MapLayer, landmarks lm: Landmarks, rules r: OpeningRules, seed: UInt64) {
        var rng = SeededRandom.derived(from: seed, 104)
        let ws = PathWorkspace()
        let o = lm.base.center, m = lm.mountainCenter, out = lm.outcrop
        func clear(_ p: GridPoint) -> Bool {
            !layer.placements.isOccupied(p) && !layer.deposits.all.contains { $0.position.chebyshev(to: p) < 2 }
        }
        func reachable(_ p: GridPoint) -> Bool {
            steps(layer.terrain, from: o, to: p, workspace: ws) != Int.max
        }
        func within(_ p: GridPoint, _ lo: Int, _ hi: Int) -> Bool {
            let d2 = p.distanceSquared(to: out)
            return d2 >= lo * lo && d2 <= hi * hi
        }
        func cells(_ hi: Int) -> [GridPoint] {
            var a: [GridPoint] = []
            for y in (out.y - hi)...(out.y + hi) {
                for x in (out.x - hi)...(out.x + hi) where layer.terrain.size.contains(GridPoint(x, y)) {
                    a.append(GridPoint(x, y))
                }
            }
            return a
        }

        // 2 つ目の鉄: 露頭から幅の内側で、岩山の岩を先に(岩山に近い順)。無ければ乾いた陸を岩場にする
        if layer.deposits[.secondIron] == nil {
            var cands: [(rank: Int, d: Int, p: GridPoint)] = []
            for p in cells(r.secondIronMax) where within(p, r.secondIronMin, r.secondIronMax) {
                guard let b = layer.terrain.biome(at: p), clear(p), lm.base.ringDistance(p) > 2 else { continue }
                if b == .rock { cands.append((0, p.distanceSquared(to: m), p)) }
                else if b == .plain || b == .forest { cands.append((1, p.distanceSquared(to: m), p)) }
            }
            cands.sort { ($0.rank, $0.d, $0.p) < ($1.rank, $1.d, $1.p) }
            if let c = cands.prefix(64).first(where: { reachable($0.p) }) {
                if layer.terrain.biome(at: c.p) != .rock { layer.terrain.set(c.p, .rock) }
                layer.deposits.add(DepositGenerator.make(id: .secondIron, at: c.p, category: .iron, rng: &rng))
            }
        }
        // 採掘回数の合計: 足りなければ 2 つ目の回数を足す
        if let first = layer.deposits[.outcrop], let second = layer.deposits[.secondIron] {
            let short = r.ironExtractionsMin - first.remainingExtractions - second.remainingExtractions
            if short > 0 { layer.deposits.update(.secondIron) { $0.remainingExtractions += short } }
        }

        // 石炭: 岩山の裏(拠点 → 岩山の向きの先)で、露頭から幅の内側。岩場を先に、無ければ乾いた陸を岩場にする
        if layer.deposits[.coal] == nil {
            let ux = m.x - o.x, uy = m.y - o.y
            var cands: [(rank: Int, d: Int, p: GridPoint)] = []
            for p in cells(r.coalFromOutcropMax) where within(p, r.coalFromOutcropMin, r.coalFromOutcropMax) {
                guard let b = layer.terrain.biome(at: p), !b.isWet, b != .ruins, lm.base.ringDistance(p) > 2, clear(p)
                else { continue }
                guard (p.x - m.x) * ux + (p.y - m.y) * uy >= 0 else { continue }   // 裏
                cands.append((b == .rock ? 0 : 1, p.distanceSquared(to: m), p))
            }
            cands.sort { ($0.rank, $0.d, $0.p) < ($1.rank, $1.d, $1.p) }
            if let c = cands.prefix(64).first(where: { reachable($0.p) }) {
                if layer.terrain.biome(at: c.p) != .rock { layer.terrain.set(c.p, .rock) }
                layer.deposits.add(DepositGenerator.make(id: .coal, at: c.p, category: .coal, rng: &rng))
            }
        }

        // 獣の巣: 露頭から幅の内側の森(森が無ければ草地を森にする)。拠点に遠い方を先に(縄張りは拠点の外)
        if layer.placements.all.contains(where: { $0.id == .openingNest }) == false,
           let tpl = POICatalog.all.first(where: { $0.id == nestTemplate }) {
            var cands: [(rank: Int, d: Int, p: GridPoint)] = []
            for p in cells(r.nestFromOutcropMax) where within(p, r.nestFromOutcropMin, r.nestFromOutcropMax) {
                let cs = tpl.footprint.cells(at: p)
                guard cs.allSatisfy({ c in
                    layer.terrain.biome(at: c).map { $0 == .forest || $0 == .plain } == true
                        && !layer.deposits.hasDeposit(at: c) && lm.base.ringDistance(c) > 2
                }), layer.placements.canPlace(tpl.footprint, at: p) else { continue }
                let forest = cs.allSatisfy { layer.terrain.biome(at: $0) == .forest }
                cands.append((forest ? 0 : 1, -p.distanceSquared(to: o), p))
            }
            cands.sort { ($0.rank, $0.d, $0.p) < ($1.rank, $1.d, $1.p) }
            if let c = cands.prefix(64).first(where: { reachable($0.p) }) {
                for q in tpl.footprint.cells(at: c.p) where layer.terrain.biome(at: q) != .forest {
                    layer.terrain.set(q, .forest)
                }
                layer.placements.place(MapPlacement(id: .openingNest, kind: .nest, templateID: tpl.id.rawValue,
                                                    anchor: c.p, footprint: tpl.footprint, isDiscovered: false))
            }
        }

        // 最初の火の置き場所: 残骸のそばに、乾いた平地か整地の空きマスを 1 つ以上(無ければ一番近い空きマスを整地にする)
        ensureFirstFireSite(&layer, radius: r.firstFireRadius ?? 3)
    }

    // MARK: 始まりの置き場と森の保証(W-23)

    /// 夜明けの昼の視界の半径(視界の決まり VisionRule をそのまま呼ぶ。式を写さない)。
    static func dawnDayRadius() -> Int { VisionRule.original.radius(isNight: false, hasTorch: false) }

    /// 最初の火の置き場と、夜明けに初めて見える置き場を決め、足りない森を補って層に持たせる(乱数を使わない)。
    /// 置き場はノアの始まりのマス(拠点の中心)から、StructureSites.spot と同じ順(距離 0 から、同じ距離なら y → x)で探す。
    static func placeOpeningSites(_ layer: inout MapLayer, landmarks lm: Landmarks, rules r: OpeningRules) {
        let start = lm.base.center
        let radius = r.firstFireRadius ?? 3
        func free(_ p: GridPoint) -> Bool {
            layer.terrain.size.contains(p) && !layer.placements.isOccupied(p) && !layer.deposits.hasDeposit(at: p)
        }
        func dry(_ p: GridPoint) -> Bool { [Biome.plain, .cleared].contains(layer.terrain.biome(at: p)) }

        let fire = ring(start, radius).first { dry($0) && free($0) } ?? firstFireSite(layer, radius: radius)
        layer.firstFireSite = fire
        guard let fire else { return }
        let ember = Set(emberCells(lm.base))
        let startRing = Set(start.neighbors8)

        // 森の保証: 近い順、同じなら y → x。置き場・ノアのマス・残骸・置いた物は除く
        func ensureForest(around c: GridPoint, radius rad: Int, min: Int, exclude: Set<GridPoint>) {
            let cells = ring(c, rad)
            var count = cells.filter { $0 != c && layer.terrain.biome(at: $0) == .forest }.count
            guard count < min else { return }
            let pool = cells.filter { p in
                p != c && p != fire && p != start && !ember.contains(p) && !exclude.contains(p) && dry(p) && free(p)
            }
            for p in pool where count < min {
                layer.terrain.set(p, .forest)
                count += 1
            }
        }
        ensureForest(around: start, radius: 1, min: r.startReachForestMin, exclude: [])
        ensureForest(around: fire, radius: 2, min: r.firstLightForestMin, exclude: [])

        // 夜明けに初めて見える置き場: 最初の夜の灯りの外・ノアの隣 8 マスの外・昼の視界の内側 1 マス以上
        let day = dawnDayRadius()
        let light = r.firstNightLightRadius
        var outer = day - 1
        while outer <= day {
            var cands: [GridPoint] = []
            for p in VisionRule.cells(center: fire, radius: outer, in: layer.terrain.size) {
                guard !VisionRule.inCircle(p, center: fire, radius: light), !startRing.contains(p), p != start,
                      !ember.contains(p), !lm.base.contains(p), dry(p), free(p) else { continue }
                cands.append(p)
            }
            cands.sort { (-lm.base.center.distanceSquared(to: $0), $0.y, $0.x) < (-lm.base.center.distanceSquared(to: $1), $1.y, $1.x) }
            if let p = cands.first { layer.dawnFindSite = p; return }
            outer += 1   // 帯を 1 マス広げる(昼の視界の縁まで)
        }
    }

    /// 残骸(wreck.home)のそばの、焚き火台を置けるマス(StructureSites.spot と同じ順: 距離 0 から、同じ距離なら y → x)。
    static func firstFireSite(_ layer: MapLayer, radius: Int) -> GridPoint? {
        guard let home = layer.placements[.homeWreck]?.anchor else { return nil }
        for p in ring(home, radius) where [Biome.plain, .cleared].contains(layer.terrain.biome(at: p)) && !layer.placements.isOccupied(p) {
            return p
        }
        return nil
    }

    static func ensureFirstFireSite(_ layer: inout MapLayer, radius: Int) {
        guard layer.placements[.homeWreck] != nil, firstFireSite(layer, radius: radius) == nil,
              let home = layer.placements[.homeWreck]?.anchor else { return }
        if let p = ring(home, radius).first(where: { layer.terrain.size.contains($0) && !layer.placements.isOccupied($0) }) { layer.terrain.set(p, .cleared) }
    }

    /// near から距離 0〜radius のマス(地図の内側だけ)。
    static func ring(_ near: GridPoint, _ radius: Int) -> [GridPoint] {
        var a: [GridPoint] = []
        for r in 0...max(0, radius) {
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r { a.append(GridPoint(near.x + dx, near.y + dy)) }
            }
        }
        return a
    }
}
