import RFKernel

/// 地図の生成(原作 `WorldMap.Generate` + R1 の目印の配置)。
///
/// 1. 4 軸の Perlin でバイオームの下地を作る(原作どおり)。拠点のまわりは「家の草地」として控えめにする。
/// 2. 目印を幾何で決めて書き込む: 森の帯(拠点と岩山の間に横たわる)→ 岩山 → 川(岸の水辺 + 歩けない流れ + 浅瀬)
///    → 遠い残骸 → 拠点の整地 11×7。
/// 3. 書き込んだ結果を距離と Pathfinder の経路で実際に測り、LandmarkRules を満たさなければ目印を引き直す(決定的)。
///    上限まで満たせなければ投げる(`allowUnverifiedFallback` のときだけ未検証の地図を記録つきで返す)。
/// 4. 残骸 2 つ・確定の鉱脈(露頭の鉄・岩山の鉄と銅・川岸の土石)を置き、チャンクごとに POI と鉱脈を置く。
///
/// 三角関数は使わない(端末と版で結果が変わり得るため)。向きは 64 方位の整数の表から引く。
enum WorldMapGenerator {
    // MARK: 幾何

    struct Vec {
        var x: Double
        var y: Double
        init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        init(_ p: GridPoint) { self.init(Double(p.x), Double(p.y)) }
        static func + (a: Vec, b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y) }
        static func - (a: Vec, b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y) }
        static func * (a: Vec, k: Double) -> Vec { Vec(a.x * k, a.y * k) }
        var length: Double { (x * x + y * y).squareRoot() }
        var normalized: Vec { let l = length; return l > 0 ? self * (1 / l) : self }
        func dot(_ o: Vec) -> Double { x * o.x + y * o.y }
        var cell: GridPoint { GridPoint(Int(x.rounded()), Int(y.rounded())) }
    }

    /// 64 方位の単位ベクトル × 10000(cos, sin を四捨五入した整数)。
    static let directions64: [(Int, Int)] = [
        (10000, 0), (9952, 980), (9808, 1951), (9569, 2903), (9239, 3827), (8819, 4714), (8315, 5556), (7730, 6344),
        (7071, 7071), (6344, 7730), (5556, 8315), (4714, 8819), (3827, 9239), (2903, 9569), (1951, 9808), (980, 9952),
        (0, 10000), (-980, 9952), (-1951, 9808), (-2903, 9569), (-3827, 9239), (-4714, 8819), (-5556, 8315), (-6344, 7730),
        (-7071, 7071), (-7730, 6344), (-8315, 5556), (-8819, 4714), (-9239, 3827), (-9569, 2903), (-9808, 1951), (-9952, 980),
        (-10000, 0), (-9952, -980), (-9808, -1951), (-9569, -2903), (-9239, -3827), (-8819, -4714), (-8315, -5556), (-7730, -6344),
        (-7071, -7071), (-6344, -7730), (-5556, -8315), (-4714, -8819), (-3827, -9239), (-2903, -9569), (-1951, -9808), (-980, -9952),
        (0, -10000), (980, -9952), (1951, -9808), (2903, -9569), (3827, -9239), (4714, -8819), (5556, -8315), (6344, -7730),
        (7071, -7071), (7730, -6344), (8315, -5556), (8819, -4714), (9239, -3827), (9569, -2903), (9808, -1951), (9952, -980),
    ]

    /// 目印の幾何の案。
    struct Layout {
        var u: Vec                  // 拠点 → 岩山の向き
        var n: Vec                  // 川の側の横向き
        var mountain: Vec
        var mountainRadius: Int
        var forestAxial: Double     // 森の帯の芯が拠点 → 岩山の線と交わる距離
        var forestHalf: Double      // 帯の半分の厚み
        var forestNeg: Double       // 川と反対側へ帯が伸びる長さ
        var riverPoints: [Vec]      // スプラインの通過点(上流 → 下流)
        var riverUpstreamDir: Vec
        var riverDownstreamDir: Vec
        var farWreck: Vec
        var fordOffset: Int
    }

    struct Stamped {
        var river: [GridPoint]
        var fords: [GridPoint]
        var farWreck: GridPoint?
        var forestCenter: GridPoint
        var forestEnds: [GridPoint]
    }

    // MARK: 入口

    static func generate(config: MapGenerationConfig, rng: inout SeededRandom) throws -> WorldMap {
        let seed = rng.next()
        let size = config.size
        guard min(size.width, size.height) >= MapGenerationConfig.minimumSide else {
            throw MapGenerationError.mapTooSmall(size)
        }
        let base = BaseArea(center: size.center)
        let field = BiomeField(seed: seed, size: size, origin: base.center, thresholds: config.biomes)
        var natural = TerrainGrid(field: field, denseCellLimit: config.denseCellLimit)
        let rules = config.landmarks
        applyHomeZone(base: base, rules: rules, terrain: &natural)
        let scale = min(1, Double(min(size.width, size.height)) / 96)

        var layoutRng = SeededRandom.derived(from: seed, 100)
        let ws = PathWorkspace()
        var chosen: (TerrainGrid, Landmarks, Int)?
        var fallback: (TerrainGrid, Landmarks, Int)?
        let attempts = max(1, config.maxLayoutAttempts)
        for attempt in 1...attempts {
            let layout = planLayout(base: base, scale: scale, rules: rules, rng: &layoutRng)
            var t = natural
            let st = stamp(layout, base: base, rules: rules, seed: seed, terrain: &t)
            if let o = config.opening { OpeningGuarantee.stampForests(&t, base: base, rules: o) }
            guard let lm = finishLandmarks(layout, stamped: st, base: base, terrain: t) else { continue }
            if fallback == nil { fallback = (t, lm, attempt) }
            if verify(lm, terrain: t, rules: rules, workspace: ws),
               config.opening.map({ OpeningGuarantee.verifyTerrain(lm, terrain: t, rules: $0, workspace: ws) }) ?? true {
                chosen = (t, lm, attempt)
                break
            }
        }
        let report: GenerationReport
        let picked: (TerrainGrid, Landmarks, Int)
        if let c = chosen {
            picked = c
            report = GenerationReport(attempts: c.2, verified: true)
        } else if config.allowUnverifiedFallback, let f = fallback {
            picked = f
            report = GenerationReport(attempts: attempts, verified: false)
        } else {
            throw MapGenerationError.layoutNotFound(attempts: attempts)
        }
        var terrain = picked.0
        let landmarks = picked.1

        ensureRuins(&terrain, landmarks: landmarks, config: config)

        var layer = MapLayer(id: .surface, terrain: terrain)
        placeFixedContent(&layer, landmarks: landmarks, seed: seed)
        if let o = config.opening { OpeningGuarantee.placeFixed(&layer, landmarks: landmarks, rules: o, seed: seed) }
        if let sites = config.sites, !sites.isEmpty { Sites.place(sites, in: &layer, landmarks: landmarks, seed: seed) }
        if let rule = config.deepVein { DeepVein.place(rule, in: &layer, landmarks: landmarks, seed: seed) }
        if let o = config.opening { OpeningGuarantee.placeOpeningSites(&layer, landmarks: landmarks, rules: o) }

        // 初期の既知(原作: 拠点の範囲 +3)
        let b = landmarks.base
        layer.visibility.markExplored(from: GridPoint(b.minCorner.x - 3, b.minCorner.y - 3),
                                      to: GridPoint(b.maxCorner.x + 3, b.maxCorner.y + 3))

        var map = WorldMap(seed: seed, config: config, landmarks: landmarks, surface: layer, report: report)
        if terrain.isDense {
            map.generateAllChunks()
        } else {
            map.ensureGenerated(around: b.center, radiusChunks: 1)
        }
        // 拠点の中心からの昼の視界
        map.updateVision(at: b.center, isNight: false, hasTorch: false)
        return map
    }

    // MARK: 1. 目印の案

    static func planLayout(base: BaseArea, scale k: Double, rules: LandmarkRules, rng: inout SeededRandom) -> Layout {
        let o = Vec(base.center)
        let d = directions64[rng.int(below: 64)]
        let u = Vec(Double(d.0) / 10000, Double(d.1) / 10000)
        let side: Double = rng.chance(percent: 50) ? 1 : -1
        let n = Vec(-u.y, u.x) * side

        // 岩山: 保証の幅の内側 1 マスで引く
        let mLo = rules.mountain.lowerBound + 1, mHi = max(mLo, rules.mountain.upperBound - 1)
        let dM = rng.double(in: mLo...mHi)
        let rM = max(2, Int((Double(rng.int(in: 4...6)) * k).rounded()))
        let mountain = o + u * dM

        // 川: 拠点の脇(最初の視界に入る)→ 大きく回り込む頂点 → 岩山の脇。岸の水辺は中心線から 2.2 マス
        let proj = Double(base.halfWidth) * abs(n.x) + Double(base.halfHeight) * abs(n.y)
        let r0Lo = proj + Double(rules.baseClearance) + 3.3
        let r0 = rng.double(in: r0Lo...max(r0Lo, rules.nearestWater.upperBound + 2.2))
        let p0 = o + n * r0 + u * rng.double(in: -2...1)
        let apex = o + u * (dM * rng.double(in: 0.30...0.38)) + n * (rng.double(in: 20...24) * k)
        let p2 = o + u * (dM + rng.double(in: -2...3) * k) + n * (Double(rM) + rng.double(in: 4.5...6) * k)
        let e0 = p0 - u * (12 * k) + n * 0.5
        let e1 = p2 + u * (12 * k) + n * 0.5

        // 森の帯: 頂点より岩山側を横切り、川の岸まで届く。反対側へは長く伸ばす(回り道は遠い)
        let forestAxial = dM * rng.double(in: 0.56...0.62)
        let forestHalf = rng.double(in: 3...4) * k
        let forestNeg = rng.double(in: 18...24) * k

        // 遠い残骸: 川の頂点の内側の岸(川沿いを行けば通り、近道からは外れる)
        let wreck = apex - n * (rng.double(in: 3...4.5) * k) + u * (rng.double(in: -1...1.5) * k)
        let fordOffset = rng.int(below: max(1, rules.fordSpacing))

        return Layout(u: u, n: n, mountain: mountain, mountainRadius: rM,
                      forestAxial: forestAxial, forestHalf: forestHalf, forestNeg: forestNeg,
                      riverPoints: [e0, p0, apex, p2, e1],
                      riverUpstreamDir: (e0 - p0).normalized, riverDownstreamDir: (e1 - p2).normalized,
                      farWreck: wreck, fordOffset: fordOffset)
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

    static let riverCoreRadius = 0.75
    static let riverBankRadius = 2.2

    /// 目印を地形に書き込む。
    static func stamp(_ L: Layout, base: BaseArea, rules: LandmarkRules, seed: UInt64,
                      terrain t: inout TerrainGrid) -> Stamped {
        let edgeNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 101))
        let o = Vec(base.center)
        func wobble(_ x: Int, _ y: Int) -> Double { 0.85 + 0.3 * edgeNoise.sample(Double(x) / 6, Double(y) / 6) }

        // 川の中心線のサンプル(Catmull-Rom。両端は地図の端までまっすぐ延ばす)
        let pts = L.riverPoints
        let ext = [pts[0] + (pts[0] - pts[1])] + pts + [pts[pts.count - 1] + (pts[pts.count - 1] - pts[pts.count - 2])]
        let reachOut = min(Double(max(t.size.width, t.size.height)) + 4, 160)
        var samples: [Vec] = []
        var spline: [Vec] = []
        var s = 0.0
        while s <= reachOut {
            samples.append(pts[0] + L.riverUpstreamDir * (reachOut - s))
            s += 0.25
        }
        for i in 1..<(ext.count - 2) {
            let a = ext[i - 1], b = ext[i], c = ext[i + 1], d = ext[i + 2]
            let steps = max(4, Int((c - b).length * 4))
            for j in 0..<steps {
                let q = catmullRom(a, b, c, d, Double(j) / Double(steps))
                samples.append(q)
                if i >= 2 && i <= 3 { spline.append(q) }   // p0 → 頂点 → p2 の区間
            }
        }
        s = 0
        while s <= reachOut {
            samples.append(pts[pts.count - 1] + L.riverDownstreamDir * s)
            s += 0.25
        }

        // 森の帯: 芯は拠点 → 岩山の線と直交し、川と反対側へ forestNeg、川の側は川の流れまで
        let fc = o + L.u * L.forestAxial
        var riverLat = 12.0
        if let q = spline.min(by: { abs(($0 - o).dot(L.u) - L.forestAxial) < abs(($1 - o).dot(L.u) - L.forestAxial) }) {
            riverLat = (q - o).dot(L.n)
        }
        let endNeg = fc - L.n * L.forestNeg
        let endPos = fc + L.n * max(2, riverLat)
        let reach = Int((max(L.forestNeg, riverLat) + L.forestHalf * 1.2 + 2).rounded(.up))
        let fcc = fc.cell
        for y in (fcc.y - reach)...(fcc.y + reach) {
            for x in (fcc.x - reach)...(fcc.x + reach) {
                let p = GridPoint(x, y)
                guard t.size.contains(p) else { continue }
                if distanceToSegment(Vec(p), endNeg, endPos) <= L.forestHalf * wobble(x, y) { t.set(p, .forest) }
            }
        }

        // 岩山
        let mc = L.mountain.cell
        let mReach = Int((Double(L.mountainRadius) * 1.2).rounded(.up))
        for y in (mc.y - mReach)...(mc.y + mReach) {
            for x in (mc.x - mReach)...(mc.x + mReach) {
                let p = GridPoint(x, y)
                if (Vec(p) - L.mountain).length <= Double(L.mountainRadius) * wobble(x, y) || p == mc { t.set(p, .rock) }
            }
        }

        // 川: 先に岸(水辺。歩ける)、次に流れ(歩けない)
        func around(_ q: Vec, _ r: Double, _ body: (GridPoint) -> Void) {
            let c = q.cell
            let ri = Int(r.rounded(.up))
            for y in (c.y - ri)...(c.y + ri) {
                for x in (c.x - ri)...(c.x + ri) {
                    let p = GridPoint(x, y)
                    if (Vec(p) - q).length <= r { body(p) }
                }
            }
        }
        for q in samples {
            around(q, riverBankRadius) { p in
                if let b = t.biome(at: p), !b.isRiver { t.set(p, .water) }
            }
        }
        var centerline: [GridPoint] = []
        for q in samples {
            around(q, riverCoreRadius) { t.set($0, .river) }
            let c = q.cell
            if t.size.contains(c), centerline.last != c { centerline.append(c) }
        }

        // 浅瀬: 中心線に沿って一定の間隔で
        var fords: [GridPoint] = []
        var i = L.fordOffset
        while i < centerline.count {
            let c = centerline[i]
            around(Vec(c), 1.6) { p in if t.biome(at: p) == .river { t.set(p, .ford) } }
            fords.append(c)
            i += max(1, rules.fordSpacing)
        }

        // 遠い残骸(2×1): 案の近くで、川の内側の岸から 2.5〜上限マス離れた陸のマス
        var wreck: GridPoint?
        var wreckScore = Double.infinity
        let target = L.farWreck.cell
        for y in (target.y - 5)...(target.y + 5) {
            for x in (target.x - 5)...(target.x + 5) {
                let p = GridPoint(x, y)
                let cells = [p, p + GridPoint(1, 0)]
                guard cells.allSatisfy({ c in t.biome(at: c).map { !$0.isWet && $0 != .rock } ?? false }) else { continue }
                var best = Double.infinity
                var nearest = p
                for c in centerline {
                    let dd = c.distance(to: p)
                    if dd < best { best = dd; nearest = c }
                }
                guard best >= 2.5 && best <= rules.farWreckToRiver else { continue }
                guard (Vec(p) - Vec(nearest)).dot(L.n) < 0 else { continue }   // 内側の岸
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

        // 拠点: 整地 11×7 と、そのまわりの輪から水・岩場・遺跡を除く
        let cl = rules.baseClearance
        for y in (base.minCorner.y - cl)...(base.maxCorner.y + cl) {
            for x in (base.minCorner.x - cl)...(base.maxCorner.x + cl) {
                let p = GridPoint(x, y)
                if base.contains(p) {
                    t.set(p, .cleared)
                } else if let b = t.biome(at: p), b.isWet || b == .rock || b == .ruins {
                    t.set(p, .plain)
                }
            }
        }
        return Stamped(river: centerline, fords: fords, farWreck: wreck, forestCenter: fc.cell,
                       forestEnds: [endNeg.cell, endPos.cell])
    }

    static func catmullRom(_ p0: Vec, _ p1: Vec, _ p2: Vec, _ p3: Vec, _ t: Double) -> Vec {
        let t2 = t * t, t3 = t2 * t
        func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return Vec(f(p0.x, p1.x, p2.x, p3.x), f(p0.y, p1.y, p2.y, p3.y))
    }

    /// 露頭と川岸を決めて Landmarks にする。決められなければ nil。
    static func finishLandmarks(_ L: Layout, stamped st: Stamped, base: BaseArea, terrain t: TerrainGrid) -> Landmarks? {
        guard let farWreck = st.farWreck, !st.river.isEmpty else { return nil }
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
        // 川岸: 岸の水辺に接する陸のマスで、拠点から 14 マスに近いもの(川沿いの道の途中)
        var bank: GridPoint?
        var bankScore = Double.infinity
        for c in st.river {
            for dy in -4...4 {
                for dx in -4...4 {
                    let p = GridPoint(c.x + dx, c.y + dy)
                    guard let b = t.biome(at: p), b == .plain || b == .forest else { continue }
                    guard p.neighbors8.contains(where: { t.biome(at: $0) == .water }) else { continue }
                    guard base.ringDistance(p) > 2, p != farWreck, p != farWreck + GridPoint(1, 0) else { continue }
                    let score = abs(p.distance(to: o) - 14)
                    if score < bankScore || (score == bankScore && p < (bank ?? p)) {
                        bankScore = score
                        bank = p
                    }
                }
            }
        }
        guard let outcrop, let bank else { return nil }
        return Landmarks(base: base, river: st.river, fords: st.fords, mountainCenter: mc, mountainRadius: L.mountainRadius,
                         forestCenter: st.forestCenter, forestEnds: st.forestEnds,
                         forestHalfThickness: Int(L.forestHalf.rounded()),
                         farWreck: farWreck, outcrop: outcrop, clayBank: bank)
    }

    // MARK: 3. 検証(書き込んだ地形を距離と経路で実際に測る)

    /// 目印の位置関係の測定値。
    struct Measurements {
        var nearestWater: Double
        var ringClean: Bool
        var riverToBase: Int
        var mountain: Double
        var outcrop: Double
        var nearestRock: Double
        var forest: Double
        var shortcutForest: Int
        var shortcutFords: Int
        var safeRatio: Double
        var farWreck: Double
        var farWreckToRiver: Double
        var farWreckOnInnerArc: Bool
        var farWreckOffShortcut: Double
        var wreckRouteNearRiver: Double
        var riverToMountain: Double
        var minEdgeMargin: Int
        var farWreckOnLand: Bool
    }

    static func measure(_ lm: Landmarks, terrain t: TerrainGrid, rules: LandmarkRules,
                        workspace ws: PathWorkspace) -> Measurements {
        let o = lm.base.center
        let size = t.size
        func nearest(_ match: (Biome) -> Bool, within r: Int) -> Double {
            var best = Double.infinity
            for y in (o.y - r)...(o.y + r) {
                for x in (o.x - r)...(o.x + r) {
                    let p = GridPoint(x, y)
                    if let b = t.biome(at: p), match(b) { best = min(best, p.distance(to: o)) }
                }
            }
            return best
        }
        let nearestWater = nearest({ $0.isWet }, within: Int(rules.nearestWater.upperBound.rounded(.up)) + 1)

        var ringClean = true
        let cl = rules.baseClearance
        for y in (lm.base.minCorner.y - cl)...(lm.base.maxCorner.y + cl) {
            for x in (lm.base.minCorner.x - cl)...(lm.base.maxCorner.x + cl) {
                let p = GridPoint(x, y)
                guard let b = t.biome(at: p) else { ringClean = false; continue }
                if lm.base.contains(p) {
                    if b != .cleared { ringClean = false }
                } else if b.isWet || b == .rock || b == .ruins {
                    ringClean = false
                }
            }
        }
        let riverToBase = lm.river.map { lm.base.ringDistance($0) }.min() ?? 0

        // 経路(霧を見ない・既定のコスト)
        let biomeAt: (GridPoint) -> Biome? = { t.biome(at: $0) }
        let shortcut = Pathfinder.findPath(size: size, from: o, to: lm.outcrop, workspace: ws, biomeAt: biomeAt)
        let safe = Pathfinder.findPath(size: size, from: o, to: lm.outcrop, options: PathOptions(fog: .ignore, avoid: [.forest]),
                                       workspace: ws, biomeAt: biomeAt)
        let wreckRoute = Pathfinder.findPath(size: size, from: o, to: lm.farWreck, workspace: ws, biomeAt: biomeAt)
        let sSteps = shortcut?.steps ?? []
        let shortcutForest = sSteps.filter { t.biome(at: $0) == .forest }.count
        let shortcutFords = sSteps.filter { t.biome(at: $0) == .ford }.count
        let safeRatio: Double
        if let s = shortcut, let f = safe, s.cost > 0 { safeRatio = Double(f.cost) / Double(s.cost) } else { safeRatio = 0 }
        let off = sSteps.map { $0.distance(to: lm.farWreck) }.min() ?? 0
        func toRiver(_ p: GridPoint) -> Double { lm.river.map { $0.distance(to: p) }.min() ?? .infinity }
        let wSteps = wreckRoute?.steps ?? []
        let near = wSteps.isEmpty ? 0
            : Double(wSteps.filter { toRiver($0) <= rules.wreckRouteRiverBand }.count) / Double(wSteps.count)

        // 遠い残骸が川の「拠点の最寄り点 → 岩山の最寄り点」の弧の上に射影されるか
        let iNear = argmin(lm.river) { $0.distanceSquared(to: o) }
        let iMount = argmin(lm.river) { $0.distanceSquared(to: lm.mountainCenter) }
        let iWreck = argmin(lm.river) { $0.distanceSquared(to: lm.farWreck) }
        let onArc = min(iNear, iMount) < iWreck && iWreck < max(iNear, iMount)

        let pts = [lm.mountainCenter, lm.forestCenter, lm.farWreck, lm.farWreck + GridPoint(1, 0), lm.outcrop, lm.clayBank]
        var margin = Int.max
        for p in pts { margin = min(margin, p.x, p.y, size.width - 1 - p.x, size.height - 1 - p.y) }
        margin = min(margin, lm.mountainCenter.x - lm.mountainRadius, lm.mountainCenter.y - lm.mountainRadius,
                     size.width - 1 - lm.mountainCenter.x - lm.mountainRadius,
                     size.height - 1 - lm.mountainCenter.y - lm.mountainRadius)
        let onLand = [lm.farWreck, lm.farWreck + GridPoint(1, 0)].allSatisfy { t.biome(at: $0) == .plain }

        return Measurements(
            nearestWater: nearestWater, ringClean: ringClean, riverToBase: riverToBase,
            mountain: lm.mountainCenter.distance(to: o), outcrop: lm.outcrop.distance(to: o),
            nearestRock: nearest({ $0 == .rock }, within: Int(lm.outcrop.distance(to: o).rounded(.up)) + 1),
            forest: lm.forestCenter.distance(to: o), shortcutForest: shortcutForest, shortcutFords: shortcutFords,
            safeRatio: safeRatio, farWreck: lm.farWreck.distance(to: o), farWreckToRiver: toRiver(lm.farWreck),
            farWreckOnInnerArc: onArc, farWreckOffShortcut: off, wreckRouteNearRiver: near,
            riverToMountain: lm.river[iMount].distance(to: lm.mountainCenter), minEdgeMargin: margin,
            farWreckOnLand: onLand)
    }

    static func verify(_ lm: Landmarks, terrain t: TerrainGrid, rules r: LandmarkRules, workspace ws: PathWorkspace) -> Bool {
        // 安い検査を先に(経路は最後)
        let m = measure(lm, terrain: t, rules: r, workspace: ws)
        return r.nearestWater.contains(m.nearestWater)
            && m.ringClean
            && m.riverToBase >= r.baseClearance + 3
            && r.mountain.contains(m.mountain)
            && r.outcrop.contains(m.outcrop)
            && m.nearestRock >= m.outcrop
            && r.forest.contains(m.forest)
            && m.shortcutForest >= r.forestOnShortcut
            && m.shortcutFords == 0
            && m.safeRatio >= r.safeRouteCostRatio
            && r.farWreck.contains(m.farWreck)
            && m.farWreckToRiver >= 2.5 && m.farWreckToRiver <= r.farWreckToRiver
            && m.farWreckOnInnerArc
            && m.farWreckOffShortcut >= r.farWreckOffShortcut
            && m.wreckRouteNearRiver >= r.wreckRouteNearRiver
            && r.riverToMountain.contains(m.riverToMountain)
            && m.riverToMountain > Double(lm.mountainRadius) + 1
            && m.minEdgeMargin >= r.edgeMargin
            && m.farWreckOnLand
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
        let fa = Vec(lm.forestEnds[0]), fb = Vec(lm.forestEnds[1])
        let protected: (GridPoint) -> Bool = { p in
            p.distance(to: lm.mountainCenter) <= Double(lm.mountainRadius) + 3
                || distanceToSegment(Vec(p), fa, fb) <= Double(lm.forestHalfThickness) + 3
                || p.distance(to: lm.farWreck) <= 4
                || p.distance(to: o) < maxD * 0.6
        }
        var best: GridPoint?
        var bestC = -1.0
        for y in 0..<size.height {
            for x in 0..<size.width {
                let p = GridPoint(x, y)
                guard !protected(p), let b = t.biome(at: p), !b.isWet else { continue }
                let c = t.field.params(at: p).contamination
                if c > bestC { bestC = c; best = p }
            }
        }
        guard let center = best else { return }
        for y in (center.y - 3)...(center.y + 3) {
            for x in (center.x - 3)...(center.x + 3) {
                let p = GridPoint(x, y)
                guard p.distance(to: center) <= 3.2, !protected(p), let b = t.biome(at: p), !b.isWet else { continue }
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
        layer.deposits.add(DepositGenerator.make(id: .clayBank, at: lm.clayBank, category: .quarry,
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
