import Foundation

/// 地図の生成(原作 `WorldMap.Generate` + R1 の目印の配置)。
///
/// 1. 4 軸の Perlin でバイオームの下地を作る(原作どおり)。
/// 2. 目印を幾何で決めて書き込む: 森(拠点と岩山の間の近道)→ 岩山 → 川(拠点の脇から大きく回り込んで岩山の脇へ)→ 拠点の整地 11×7。
/// 3. 書き込んだ結果を実際に測り、LandmarkRules の距離の範囲を満たさなければ目印の引き直し(決定的)。
/// 4. 残骸 2 つ・確定の鉱脈(露頭の鉄・岩山の鉄と銅・川岸の土石)を置き、チャンクごとに POI と鉱脈を置く。
enum WorldMapGenerator {
    // MARK: 幾何

    struct Vec {
        var x: Double
        var y: Double
        init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        static func + (a: Vec, b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y) }
        static func - (a: Vec, b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y) }
        static func * (a: Vec, k: Double) -> Vec { Vec(a.x * k, a.y * k) }
        var length: Double { (x * x + y * y).squareRoot() }
        var normalized: Vec { let l = length; return l > 0 ? self * (1 / l) : self }
        func dot(_ o: Vec) -> Double { x * o.x + y * o.y }
        var cell: GridPoint { GridPoint(Int(x.rounded()), Int(y.rounded())) }
        init(_ p: GridPoint) { self.init(Double(p.x), Double(p.y)) }
    }

    /// 目印の幾何の案(拠点の中心を原点とした実数座標を地図の座標に直したもの)。
    struct Layout {
        var mountain: Vec
        var mountainRadius: Int
        var forest: Vec
        var forestRadius: Int
        var riverPoints: [Vec]      // スプラインの通過点(上流 → 下流)
        var riverUpstreamDir: Vec   // 上流の端から先へまっすぐ延ばす向き
        var riverDownstreamDir: Vec
        var farWreck: Vec
    }

    // MARK: 入口

    static func generate(config: MapGenerationConfig, rng: inout SeededRandom) -> WorldMap {
        let seed = rng.next()
        let size = config.size
        let base = BaseArea(center: size.center)
        let field = BiomeField(seed: seed, size: size, origin: base.center, thresholds: config.biomes)
        var natural = TerrainGrid(field: field, denseCellLimit: config.denseCellLimit)
        let rules = config.landmarks
        applyHomeZone(base: base, rules: rules, terrain: &natural)
        let scale = min(1, Double(min(size.width, size.height)) / 96)

        var layoutRng = SeededRandom.derived(from: seed, 100)
        var chosen: (TerrainGrid, Landmarks)?
        var fallback: (TerrainGrid, Landmarks)?
        for _ in 0..<max(1, config.maxLayoutAttempts) {
            let layout = planLayout(base: base, scale: scale, rules: rules, rng: &layoutRng)
            var t = natural
            let stamped = stamp(layout, base: base, rules: rules, seed: seed, terrain: &t)
            guard let wreck = stamped.farWreck,
                  let lm = finishLandmarks(layout, river: stamped.river, farWreck: wreck, base: base, terrain: t)
            else { continue }
            if fallback == nil { fallback = (t, lm) }
            if verify(lm, terrain: t, rules: rules) {
                chosen = (t, lm)
                break
            }
        }
        guard case (var terrain, let landmarks)? = chosen ?? fallback else {
            preconditionFailure("地図の目印を置けない(地図が小さすぎる): \(size)")
        }

        ensureRuins(&terrain, landmarks: landmarks, config: config)

        var layer = MapLayer(id: .surface, terrain: terrain)
        placeFixedContent(&layer, landmarks: landmarks, seed: seed)

        // 初期の既知(原作: 拠点の範囲 +3)と、拠点の中心からの昼の視界
        let b = landmarks.base
        layer.visibility.markExplored(from: GridPoint(b.minCorner.x - 3, b.minCorner.y - 3),
                                      to: GridPoint(b.maxCorner.x + 3, b.maxCorner.y + 3))
        layer.visibility.update(center: b.center, radius: config.vision.radius(isNight: false, hasTorch: false))

        var map = WorldMap(seed: seed, config: config, landmarks: landmarks, surface: layer)
        if terrain.isDense {
            map.generateAllChunks()
        } else {
            map.ensureGenerated(around: b.center, radiusChunks: 1)
        }
        _ = map.updateVision(at: b.center, isNight: false, hasTorch: false)
        return map
    }

    // MARK: 1. 目印の案

    static func planLayout(base: BaseArea, scale k: Double, rules: LandmarkRules, rng: inout SeededRandom) -> Layout {
        let o = Vec(base.center)
        let theta = rng.unit() * 2 * Double.pi
        let u = Vec(cos(theta), sin(theta))
        let side: Double = rng.chance(percent: 50) ? 1 : -1
        let n = Vec(-u.y, u.x) * side

        // 岩山: 保証の幅の内側 1 マスで引く
        let mLo = rules.mountain.lowerBound + 1, mHi = max(mLo, rules.mountain.upperBound - 1)
        let dM = rng.double(in: mLo...mHi)
        let rM = max(2, Int((Double(rng.int(in: 4...6)) * k).rounded()))
        let mountain = o + u * dM

        // 森: 拠点と岩山の間(川と反対側へ少し寄せる)
        let ft = rng.double(in: 0.42...0.58)
        let forest = o + u * (dM * ft) - n * rng.double(in: 0...2) * k
        let rF = max(2, Int((Double(rng.int(in: 5...7)) * k).rounded()))

        // 川: 拠点の脇(最初の視界に入る)→ 大きく回り込む頂点 → 岩山の脇
        let proj = Double(base.halfWidth) * abs(n.x) + Double(base.halfHeight) * abs(n.y)
        let r0Lo = proj + Double(rules.baseClearance) + 1.6
        let r0 = rng.double(in: r0Lo...max(r0Lo, rules.nearestWater.upperBound + 0.8))
        let p0 = o + n * r0 + u * rng.double(in: -2...1)
        let apex = o + u * (dM * rng.double(in: 0.5...0.62)) + n * rng.double(in: 16...20) * k
        let p2 = o + u * (dM + rng.double(in: -2...3) * k) + n * (Double(rM) + rng.double(in: 3...5) * k)
        let e0 = p0 - u * (12 * k) + n * 0.5
        let e1 = p2 + u * (12 * k) + n * 0.5

        // 遠い残骸: 川の頂点を過ぎたあたりの内側の岸(川沿いを行けば通り、近道からは外れる)
        let wreck = apex - n * rng.double(in: 3...4.5) * k + u * rng.double(in: 1...5) * k

        return Layout(mountain: mountain, mountainRadius: rM, forest: forest, forestRadius: rF,
                      riverPoints: [e0, p0, apex, p2, e1],
                      riverUpstreamDir: (e0 - p0).normalized, riverDownstreamDir: (e1 - p2).normalized,
                      farWreck: wreck)
    }

    // MARK: 2. 書き込み

    /// 家の草地: 拠点のまわりの下地を控えめな判定で作り直す(外側 6 マスで通常の判定へ戻す)。
    static func applyHomeZone(base: BaseArea, rules: LandmarkRules, terrain t: inout TerrainGrid) {
        let zr = rules.homeZoneRadius
        let outer = t.field.thresholds
        let o = base.center
        let reachZone = Int((zr + 6).rounded(.up))
        for y in (o.y - reachZone)...(o.y + reachZone) {
            for x in (o.x - reachZone)...(o.x + reachZone) {
                let p = GridPoint(x, y)
                guard t.size.contains(p) else { continue }
                let d = p.distance(to: o)
                guard d <= zr + 6 else { continue }
                let th = BiomeThresholds.blend(.home, outer, (d - zr) / 6)
                t.set(p, th.biome(t.field.params(at: p)))
            }
        }
    }

    /// 目印を地形に書き込み、川の中心線(マスの列)を返す。
    static func stamp(_ L: Layout, base: BaseArea, rules: LandmarkRules, seed: UInt64,
                      terrain t: inout TerrainGrid) -> (river: [GridPoint], farWreck: GridPoint?) {
        let edgeNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 101))

        func blob(_ c: Vec, _ r: Int, _ biome: Biome) {
            let reach = Int((Double(r) * 1.2).rounded(.up))
            let cc = c.cell
            for y in (cc.y - reach)...(cc.y + reach) {
                for x in (cc.x - reach)...(cc.x + reach) {
                    let p = GridPoint(x, y)
                    let d = (Vec(p) - c).length
                    let wobble = 0.85 + 0.3 * edgeNoise.sample(Double(x) / 6, Double(y) / 6)
                    if d <= Double(r) * wobble || p == cc { t.set(p, biome) }
                }
            }
        }
        blob(L.forest, L.forestRadius, .forest)
        blob(L.mountain, L.mountainRadius, .rock)

        // 川: Catmull-Rom で通過点をなめらかにつなぎ、両端は地図の端までまっすぐ延ばす
        var samples: [Vec] = []
        let pts = L.riverPoints
        let ext = [pts[0] + (pts[0] - pts[1])] + pts + [pts[pts.count - 1] + (pts[pts.count - 1] - pts[pts.count - 2])]
        let reachOut = Double(max(t.size.width, t.size.height)) + 4
        let upstreamLen = min(reachOut, 160)
        var s = 0.0
        while s <= upstreamLen {   // 上流の延長(遠い方から)
            samples.append(pts[0] + L.riverUpstreamDir * (upstreamLen - s))
            s += 0.25
        }
        for i in 1..<(ext.count - 2) {
            let a = ext[i - 1], b = ext[i], c = ext[i + 1], d = ext[i + 2]
            let segLen = (c - b).length
            let steps = max(4, Int(segLen * 4))
            for j in 0..<steps {
                let tt = Double(j) / Double(steps)
                samples.append(catmullRom(a, b, c, d, tt))
            }
        }
        s = 0
        while s <= upstreamLen {   // 下流の延長
            samples.append(pts[pts.count - 1] + L.riverDownstreamDir * s)
            s += 0.25
        }

        var centerline: [GridPoint] = []
        for q in samples {
            let c = q.cell
            if t.size.contains(c), centerline.last != c { centerline.append(c) }
            for y in (c.y - 1)...(c.y + 1) {
                for x in (c.x - 1)...(c.x + 1) {
                    let p = GridPoint(x, y)
                    if (Vec(p) - q).length <= 1.0 { t.set(p, .water) }
                }
            }
        }

        // 遠い残骸(2×1): 案の位置の近くで、川の中心線から 2.5〜6 マス離れた陸のマスを選び、平地にする
        var wreck: GridPoint?
        var wreckScore = Double.infinity
        let target = L.farWreck.cell
        for y in (target.y - 4)...(target.y + 4) {
            for x in (target.x - 4)...(target.x + 4) {
                let p = GridPoint(x, y)
                let cells = [p, p + GridPoint(1, 0)]
                guard cells.allSatisfy({ t.size.contains($0) && t.biome(at: $0) != .water }) else { continue }
                let toRiver = cells.map { c in centerline.map { $0.distance(to: c) }.min() ?? .infinity }.min()!
                guard toRiver >= 2.5 && toRiver <= 6 else { continue }
                let score = p.distance(to: target)
                if score < wreckScore || (score == wreckScore && p < (wreck ?? p)) {
                    wreckScore = score
                    wreck = p
                }
            }
        }
        if let w = wreck {
            t.set(w, .plain)
            t.set(w + GridPoint(1, 0), .plain)
        }

        // 拠点: 整地 11×7 と、そのまわりの輪から水辺・岩場・遺跡を除く
        let cl = rules.baseClearance
        for y in (base.minCorner.y - cl)...(base.maxCorner.y + cl) {
            for x in (base.minCorner.x - cl)...(base.maxCorner.x + cl) {
                let p = GridPoint(x, y)
                if base.contains(p) {
                    t.set(p, .cleared)
                } else if let b = t.biome(at: p), b == .water || b == .rock || b == .ruins {
                    t.set(p, .plain)
                }
            }
        }
        return (centerline, wreck)
    }

    static func catmullRom(_ p0: Vec, _ p1: Vec, _ p2: Vec, _ p3: Vec, _ t: Double) -> Vec {
        let t2 = t * t, t3 = t2 * t
        func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return Vec(f(p0.x, p1.x, p2.x, p3.x), f(p0.y, p1.y, p2.y, p3.y))
    }

    /// 露頭と川岸を決めて Landmarks にする。決められなければ nil。
    static func finishLandmarks(_ L: Layout, river: [GridPoint], farWreck: GridPoint, base: BaseArea,
                                terrain t: TerrainGrid) -> Landmarks? {
        let mc = L.mountain.cell
        let o = base.center
        // 露頭: 岩山の岩のうち拠点にいちばん近いマス
        var outcrop: GridPoint?
        let reach = L.mountainRadius + 2
        for y in (mc.y - reach)...(mc.y + reach) {
            for x in (mc.x - reach)...(mc.x + reach) {
                let p = GridPoint(x, y)
                guard t.biome(at: p) == .rock, p.distance(to: mc) <= Double(L.mountainRadius) * 1.2 + 0.5 else { continue }
                if let cur = outcrop {
                    let a = p.distanceSquared(to: o), b = cur.distanceSquared(to: o)
                    if a < b || (a == b && p < cur) { outcrop = p }
                } else {
                    outcrop = p
                }
            }
        }
        // 川岸: 川に接する陸のマスで、拠点から 14 マスに近いもの(川沿いの道の途中)
        var bank: GridPoint?
        var bankScore = Double.infinity
        for c in river {
            for p in c.neighbors8 + [c] {
                guard let b = t.biome(at: p), b == .plain || b == .forest else { continue }
                guard p.neighbors8.contains(where: { t.biome(at: $0) == .water }) else { continue }
                guard base.ringDistance(p) > 2 else { continue }
                let score = abs(p.distance(to: o) - 14)
                if score < bankScore || (score == bankScore && p < (bank ?? p)) {
                    bankScore = score
                    bank = p
                }
            }
        }
        guard let outcrop, let bank, !river.isEmpty else { return nil }
        return Landmarks(base: base, river: river, mountainCenter: mc, mountainRadius: L.mountainRadius,
                         forestCenter: L.forest.cell, forestRadius: L.forestRadius,
                         farWreck: farWreck, outcrop: outcrop, clayBank: bank)
    }

    // MARK: 3. 検証(書き込んだ地形を実際に測る)

    /// 目印の位置関係の測定値。テストと検証が同じ測り方を使う。
    struct Measurements {
        var nearestWater: Double
        var ringClean: Bool
        var mountain: Double
        var outcrop: Double
        var forest: Double
        var forestOnShortcut: Int
        var waterOnShortcut: Int
        var farWreck: Double
        var farWreckToRiver: Double
        var farWreckOffShortcut: Double
        var riverToMountain: Double
        var riverDetourRatio: Double
        var minEdgeMargin: Int
        var farWreckOnLand: Bool
        /// 拠点の中心からいちばん近い岩場のマス(露頭より近い岩場が無いこと)。
        var nearestRock: Double
    }

    static func measure(_ lm: Landmarks, terrain t: TerrainGrid, rules: LandmarkRules) -> Measurements {
        let o = lm.base.center
        let size = t.size

        // いちばん近い水辺(拠点の中心から半径 30 の窓で)
        var nearest = Double.infinity
        let win = 30
        for y in (o.y - win)...(o.y + win) {
            for x in (o.x - win)...(o.x + win) {
                let p = GridPoint(x, y)
                if t.biome(at: p) == .water { nearest = min(nearest, p.distance(to: o)) }
            }
        }

        // いちばん近い岩場(半径 40 の窓で)
        var nearestRock = Double.infinity
        for y in (o.y - 40)...(o.y + 40) {
            for x in (o.x - 40)...(o.x + 40) {
                let p = GridPoint(x, y)
                if t.biome(at: p) == .rock { nearestRock = min(nearestRock, p.distance(to: o)) }
            }
        }

        // 拠点の整地と輪
        var ringClean = true
        let cl = rules.baseClearance
        for y in (lm.base.minCorner.y - cl)...(lm.base.maxCorner.y + cl) {
            for x in (lm.base.minCorner.x - cl)...(lm.base.maxCorner.x + cl) {
                let p = GridPoint(x, y)
                guard let b = t.biome(at: p) else { ringClean = false; continue }
                if lm.base.contains(p) {
                    if b != .cleared { ringClean = false }
                } else if b == .water || b == .rock || b == .ruins {
                    ringClean = false
                }
            }
        }

        // 拠点 → 岩山の直線
        let line = bresenham(o, lm.mountainCenter)
        let forestOn = line.filter { t.biome(at: $0) == .forest }.count
        let waterOn = line.filter { t.biome(at: $0) == .water }.count

        // 遠い残骸と川
        let toRiver = lm.river.map { $0.distance(to: lm.farWreck) }.min() ?? .infinity
        let off = distanceToSegment(Vec(lm.farWreck), Vec(o), Vec(lm.mountainCenter))

        // 川沿いの道: 拠点 → 拠点にいちばん近い川 → 川に沿って → 岩山にいちばん近い川 → 岩山
        let iNear = argmin(lm.river) { $0.distanceSquared(to: o) }
        let iMount = argmin(lm.river) { $0.distanceSquared(to: lm.mountainCenter) }
        var arc = 0.0
        let (a, b) = (min(iNear, iMount), max(iNear, iMount))
        if b > a { for i in a..<b { arc += lm.river[i].distance(to: lm.river[i + 1]) } }
        let route = lm.river[iNear].distance(to: o) + arc + lm.river[iMount].distance(to: lm.mountainCenter)
        let direct = max(1, lm.mountainCenter.distance(to: o))

        // 地図の端との空き
        let pts = [lm.mountainCenter, lm.forestCenter, lm.farWreck, lm.farWreck + GridPoint(1, 0), lm.outcrop, lm.clayBank]
        var margin = Int.max
        for p in pts {
            margin = min(margin, p.x, p.y, size.width - 1 - p.x, size.height - 1 - p.y)
        }
        margin = min(margin, lm.mountainCenter.x - lm.mountainRadius, lm.mountainCenter.y - lm.mountainRadius,
                     size.width - 1 - lm.mountainCenter.x - lm.mountainRadius,
                     size.height - 1 - lm.mountainCenter.y - lm.mountainRadius)

        let wreckCells = [lm.farWreck, lm.farWreck + GridPoint(1, 0)]
        let onLand = wreckCells.allSatisfy { t.biome(at: $0) == .plain }

        return Measurements(
            nearestWater: nearest, ringClean: ringClean,
            mountain: lm.mountainCenter.distance(to: o), outcrop: lm.outcrop.distance(to: o),
            forest: lm.forestCenter.distance(to: o), forestOnShortcut: forestOn, waterOnShortcut: waterOn,
            farWreck: lm.farWreck.distance(to: o), farWreckToRiver: toRiver, farWreckOffShortcut: off,
            riverToMountain: lm.river[iMount].distance(to: lm.mountainCenter), riverDetourRatio: route / direct,
            minEdgeMargin: margin, farWreckOnLand: onLand, nearestRock: nearestRock)
    }

    static func verify(_ lm: Landmarks, terrain t: TerrainGrid, rules r: LandmarkRules) -> Bool {
        let m = measure(lm, terrain: t, rules: r)
        return r.nearestWater.contains(m.nearestWater)
            && m.ringClean
            && r.mountain.contains(m.mountain)
            && r.outcrop.contains(m.outcrop)
            && r.forest.contains(m.forest)
            && m.forestOnShortcut >= r.forestOnShortcut
            && m.waterOnShortcut == 0
            && r.farWreck.contains(m.farWreck)
            && m.farWreckToRiver <= r.farWreckToRiver
            && m.farWreckToRiver >= 2
            && m.farWreckOffShortcut >= r.farWreckOffShortcut
            && r.riverToMountain.contains(m.riverToMountain)
            && m.riverToMountain > Double(lm.mountainRadius) + 1
            && m.riverDetourRatio >= r.riverDetourRatio
            && m.minEdgeMargin >= r.edgeMargin
            && m.farWreckOnLand
            && m.nearestRock >= m.outcrop
    }

    static func bresenham(_ a: GridPoint, _ b: GridPoint) -> [GridPoint] {
        var out: [GridPoint] = []
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            out.append(GridPoint(x, y))
            if x == b.x && y == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
        return out
    }

    static func distanceToSegment(_ p: Vec, _ a: Vec, _ b: Vec) -> Double {
        let ab = b - a
        let l2 = ab.dot(ab)
        guard l2 > 0 else { return (p - a).length }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        return (p - (a + ab * t)).length
    }

    static func argmin<T>(_ xs: [T], _ key: (T) -> Int) -> Int {
        var best = 0, bestKey = Int.max
        for (i, x) in xs.enumerated() {
            let k = key(x)
            if k < bestKey { best = i; bestKey = k }
        }
        return best
    }

    // MARK: 遺跡が足りない小さい地図

    static func ensureRuins(_ t: inout TerrainGrid, landmarks lm: Landmarks, config: MapGenerationConfig) {
        guard t.isDense, config.minimumRuinsCells > 0 else { return }
        guard t.count(.ruins) < config.minimumRuinsCells else { return }
        let o = lm.base.center
        let size = t.size
        let maxD = Double(max(size.width, size.height)) / 2
        let protected: (GridPoint) -> Bool = { p in
            p.distance(to: lm.mountainCenter) <= Double(lm.mountainRadius) + 3
                || p.distance(to: lm.forestCenter) <= Double(lm.forestRadius) + 3
                || p.distance(to: lm.farWreck) <= 4
                || p.distance(to: o) < maxD * 0.6
        }
        // いちばん汚れたマス(拠点から遠く、目印から離れたところ)
        var best: GridPoint?
        var bestC = -1.0
        for y in 0..<size.height {
            for x in 0..<size.width {
                let p = GridPoint(x, y)
                guard !protected(p) else { continue }
                let c = t.field.params(at: p).contamination
                if c > bestC { bestC = c; best = p }
            }
        }
        guard let center = best else { return }
        for y in (center.y - 3)...(center.y + 3) {
            for x in (center.x - 3)...(center.x + 3) {
                let p = GridPoint(x, y)
                guard p.distance(to: center) <= 3.2, !protected(p), let b = t.biome(at: p), b != .water else { continue }
                t.set(p, .ruins)
            }
        }
    }

    // MARK: 4. 確定の配置物と鉱脈

    static func placeFixedContent(_ layer: inout MapLayer, landmarks lm: Landmarks, seed: UInt64) {
        var rng = SeededRandom.derived(from: seed, 102)
        // 自分たちの残骸: 拠点の中央 3×2。原作の残骸漁りは 10 回まで
        let home = MapPlacement(id: .homeWreck, kind: .wreck, templateID: "wreck.home",
                                anchor: lm.base.center - GridPoint(1, 1), footprint: .rect(width: 3, height: 2),
                                isDiscovered: true, remainingUses: 10)
        layer.placements.place(home)
        let far = MapPlacement(id: .farWreck, kind: .wreck, templateID: "wreck.far",
                               anchor: lm.farWreck, footprint: .rect(width: 2, height: 1), isDiscovered: false)
        layer.placements.place(far)

        // 露頭: 鉄、純度 20〜35%(seed で変わる。最初の鉄が粗鉄塊と鉄塊の境目になる幅)
        layer.deposits.add(DepositGenerator.make(id: .outcrop, at: lm.outcrop, category: .iron,
                                                 rng: &rng, primaryPercent: 20...35))
        // 岩山の奥に鉄と銅をもう 1 つずつ(原作の開始時の鉱脈: 鉄・銅・土石)
        var rocks: [GridPoint] = []
        let r = lm.mountainRadius + 1
        for y in (lm.mountainCenter.y - r)...(lm.mountainCenter.y + r) {
            for x in (lm.mountainCenter.x - r)...(lm.mountainCenter.x + r) {
                let p = GridPoint(x, y)
                if layer.terrain.biome(at: p) == .rock, p.distance(to: lm.outcrop) >= 2 { rocks.append(p) }
            }
        }
        for (i, cat) in [DepositCategory.iron, .copper].enumerated() where !rocks.isEmpty {
            let p = rocks.remove(at: rng.int(below: rocks.count))
            layer.deposits.add(DepositGenerator.make(id: DepositID("deposit.mountain.\(i)"), at: p, category: cat, rng: &rng))
            rocks.removeAll { $0.chebyshev(to: p) < 2 }
        }
        // 川岸の土石(粘土質の河岸 = 見た目の 3 番)
        layer.deposits.add(DepositGenerator.make(id: DepositID("deposit.claybank"), at: lm.clayBank, category: .quarry,
                                                 rng: &rng, appearanceVariant: 3))
    }

    // MARK: 5. チャンクごとの POI と鉱脈(原作 GenerateChunkPOIs。8×8 の区画、区画ごとの確率)

    static func populateChunk(_ layer: inout MapLayer, chunk: ChunkCoord, seed: UInt64, landmarks lm: Landmarks,
                              config: MapGenerationConfig, minerals: MineralField) {
        let cs = config.chunkSize
        let start = GridPoint(chunk.cx * cs, chunk.cy * cs)
        let g = max(1, cs / 8)
        var rng = SeededRandom.derived(from: seed, 200, chunk.cx, chunk.cy)
        func inChunk(_ p: GridPoint) -> Bool {
            p.x >= start.x && p.y >= start.y && p.x < start.x + cs && p.y < start.y + cs && layer.size.contains(p)
        }
        for gy in 0..<8 {
            for gx in 0..<8 {
                // POI
                if rng.chance(percent: config.poiPercentPerCell) {
                    let p = start + GridPoint(gx * g + rng.int(below: g), gy * g + rng.int(below: g))
                    let pick = rng.int(below: 10_000)
                    if inChunk(p), let b = layer.terrain.biome(at: p), b != .cleared,
                       lm.base.ringDistance(p) > config.poiBaseExclusion {
                        let candidates = POICatalog.templates(for: b)
                        let total = candidates.reduce(0) { $0 + $1.weight }
                        if total > 0 {
                            var roll = pick % total
                            var chosen = candidates[candidates.count - 1]
                            for c in candidates {
                                if roll < c.weight { chosen = c; break }
                                roll -= c.weight
                            }
                            let cells = chosen.footprint.cells(at: p)
                            let ok = cells.allSatisfy { c in
                                inChunk(c) && (layer.terrain.biome(at: c).map { chosen.biomes.contains($0) } ?? false)
                                    && !layer.deposits.hasDeposit(at: c)
                            } && layer.placements.canPlace(chosen.footprint, at: p)
                            if ok {
                                let uses = chosen.scrap.map { rng.int(in: $0) }
                                layer.placements.place(MapPlacement(
                                    id: PlacementID("poi.\(chunk.cx).\(chunk.cy).\(gx).\(gy)"), kind: chosen.kind,
                                    templateID: chosen.id.rawValue, anchor: p, footprint: chosen.footprint,
                                    isDiscovered: false, remainingUses: uses))
                            }
                        }
                    }
                }
                // 鉱脈(岩場と遺跡で、地下の鉱物が地表に出ているところ。原作 HasSurfaceDeposit)
                if rng.chance(percent: config.depositPercentPerCell) {
                    let p = start + GridPoint(gx * g + rng.int(below: g), gy * g + rng.int(below: g))
                    var depRng = SeededRandom.derived(from: seed, 201, p.x, p.y)
                    guard inChunk(p), let b = layer.terrain.biome(at: p), b == .rock || b == .ruins,
                          lm.base.ringDistance(p) > 2, !layer.placements.isOccupied(p), !layer.deposits.hasDeposit(at: p)
                    else { continue }
                    let geo = layer.terrain.field.params(at: p).geology
                    let info = minerals.minerals(at: p, depth: 0, geology: geo)
                    let category: DepositCategory
                    if info.hasMineral {
                        category = info.dominantCategory
                    } else if b == .rock && depRng.chance(percent: 30) {
                        category = .quarry
                    } else {
                        continue
                    }
                    layer.deposits.add(DepositGenerator.make(id: DepositID("deposit.\(p.x).\(p.y)"), at: p,
                                                             category: category, rng: &depRng))
                }
            }
        }
    }
}
