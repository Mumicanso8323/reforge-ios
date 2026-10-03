import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// 最初の 10 分の版 SL-40(担当 U14): ボットが始まりの火から最初のシェルターまで通しで遊び、出来事の時刻を並べる。
/// 非公開の層があるときだけ回す。
///
/// - 時刻は「実時間の目安」: 昼はゲームの 160 秒 = 実時間 1 秒。保留の間は押した秒数。場面を送るタップは 3〜4 秒。
/// - 行為・人・建造物は内容から引く(このテストは内容の ID を持たない)。
///   くべる = 焚き火に燃料を足す効果を持つ行為。残り火 = 確率なし・費用なしで点ける行為。
///   採る = その品を産む地形の行為(費用なし・短い順)。残骸 = 自分たちの残骸(wreck.home)への行為。
///   シェルター = 寝床(housing)を持つ建造物のうち費用の少ない順。番 = 最後に加わった仲間。
/// - 歩くのは、行為の場所へは時間を進めて移す(1 秒 4 マス)。地形を見つけに行くときは最後を本物の歩く命令で(着いた時の解禁のため)。
/// - REFORGE_TENMIN_SEEDS: seed の数(既定 5)。REFORGE_TENMIN_STACK=1: 夜の前に火床の薪の山へ積む(本体の .stack を直接送る)。
final class FirstTenMinutesBotTests: XCTestCase {
    struct Bot {
        let content: ContentDB
        let sim: Simulation
        let fb: FrameBuilder
        var w: WorldState
        var real: Double = 0
        var log: [(EventID, Double)] = []
        var seen: Set<EventID> = []
        /// 採った(または断られた)間を置く採取のマス。同じマスを探し直さない。
        var spent: Set<GridPoint> = []
        /// 行為ごとの最後の断り(診断)。見つからなかったときは「無い」。
        var rejects: [String: String] = [:]

        init(content: ContentDB, seed: UInt64) {
            self.content = content
            sim = Simulation(content: content)
            fb = FrameBuilder(content: content)
            w = WorldFactory(content: content, mapGenerator: RFMapGenerator()).newWorld(seed: seed)
        }

        static let realPerStep = Double(SimStep.gameSeconds) / 160

        var here: WorldPoint { w.people[.noah]!.position! }
        var members: [PersonID] { w.people.members }

        func count(_ item: ItemID) -> Int { ConditionEvaluator.stockCount(Ingredient(item: item, quantity: 1), w) }

        mutating func note() {
            for id in w.narrative.fired.keys.sorted(by: { $0.rawValue < $1.rawValue }) where !seen.contains(id) {
                seen.insert(id)
                log.append((id, real))
            }
        }

        mutating func steps(_ n: Int) {
            for _ in 0..<n {
                _ = sim.runSteps(1, &w)
                if w.clock.phase == .day { real += Self.realPerStep }
                note()
            }
        }

        /// 序を送り、暗い場面の行為を押し切る。
        mutating func lightFire() {
            var n = 0
            while w.narrative.scene != nil && n < 30 { _ = sim.apply(.narrative(.advanceScene), to: &w); n += 1; real += 4 }
            guard let act = fb.build(w, revision: 0, previous: nil, report: nil).darkStart?.action else { return }
            _ = sim.apply(act.start, to: &w)
            var carry: Int64 = 0
            n = 0
            while w.clock.held && n < 20000 { _ = sim.advanceHeld(&w, realSeconds: 0.1, carry: &carry); n += 1; real += 0.1 }
            _ = sim.apply(act.end, to: &w)
            note()
        }

        /// ノアの近くで行為 id を探す(足元カードの行為)。近い順。
        func find(_ id: InteractionID, radius: Int = 12) -> FootCard.Action? {
            let c = here.point
            let cooling = content.interactions[id]?.cooldownDays != nil
            for r in 0...radius {
                for dy in -r...r {
                    for dx in -r...r where max(abs(dx), abs(dy)) == r {
                        let g = c + GridPoint(dx, dy)
                        if cooling, spent.contains(g) { continue }
                        if let a = fb.footCard(w, at: g)?.actions.first(where: { $0.id == id }) { return a }
                    }
                }
            }
            return nil
        }

        /// 行為の場所へ移り(時間は 1 秒 4 マスで進める)、終わるまで押す。
        @discardableResult
        mutating func act(_ id: InteractionID, radius: Int = 12) -> Bool {
            guard let a = find(id, radius: radius) else { rejects[id.rawValue] = "無い"; return false }
            let d = max(abs(a.at.point.x - here.point.x), abs(a.at.point.y - here.point.y))
            steps(Int(Double(d) / 4 / Self.realPerStep))
            w.people[.noah]?.position = a.at
            if content.interactions[id]?.cooldownDays != nil { spent.insert(a.at.point) }
            let r = sim.apply(a.start, to: &w)
            guard r.rejection == nil else { rejects[id.rawValue] = r.rejection!.reason.rawValue; return false }
            var n = 0
            while w.exploration.active[.noah] != nil && n < 2000 { steps(1); n += 1 }
            _ = sim.apply(a.end, to: &w)
            note()
            return true
        }

        /// 全画面の場面はタップで送る(ふきだしは時間で流れる)。
        mutating func readScenes() {
            var n = 0
            while let s = w.narrative.scene, content.scenes[s.scene]?.style.map({ "\($0)" }) == "stage", n < 20 {
                _ = sim.apply(.narrative(.advanceScene), to: &w)
                real += 3
                n += 1
            }
        }

        /// 日没までのゲーム秒(昼の間)。
        var toDusk: Int64 { Int64(content.clock.dayGameHours * 3600) - (w.clock.now - w.clock.dayStartedAt).seconds }

        /// 火床を持つ最初の建造物(始まりの火)。
        func campfire() -> EntityID? { Hearths.structureHearths(w, content).first }

        mutating func goHome() {
            guard let f = campfire(), let pl = w.placements.items[f] else { return }
            let at = WorldPoint(pl.at.layer, pl.at.point + GridPoint(0, 1))
            w.people[.noah]?.position = at
        }

        /// 本物の歩く命令で歩く(着くまで時間を進める)。
        mutating func walk(to g: GridPoint) {
            let to = WorldPoint(here.layer, g)
            _ = sim.apply(.crew(.walk(to: to)), to: &w)
            var m = 0
            while w.people[.noah]?.motion != nil && m < 2000 { steps(1); m += 1 }
        }

        /// その札の地形のいちばん近いマスのそばまで行く(遠くは時間を進めて移り、最後の数マスを歩く)。
        mutating func discover(tag: String, radius: Int = 48) {
            guard let layer = w.map[here.layer] else { return }
            let c = here.point
            func has(_ p: GridPoint) -> Bool {
                guard let t = layer.terrain(at: p) else { return false }
                return (content.terrains[t]?.tags ?? [t.rawValue]).contains(tag)
            }
            func passable(_ p: GridPoint) -> Bool {
                guard layer.size.contains(p), let t = layer.terrain(at: p), let d = content.terrains[t] else { return false }
                return d.passable != false && d.isWater != true
            }
            for r in 1...radius {
                for dy in -r...r {
                    for dx in -r...r where max(abs(dx), abs(dy)) == r {
                        let p = c + GridPoint(dx, dy)
                        guard has(p), let stand = p.neighbors8.first(where: { passable($0) && !has($0) }) ?? (passable(p) ? p : nil)
                        else { continue }
                        let near = stand + GridPoint(0, stand.y > c.y ? -3 : 3)
                        if passable(near) {
                            let d = max(abs(near.x - c.x), abs(near.y - c.y))
                            steps(Int(Double(d) / 4 / Self.realPerStep))
                            let at = WorldPoint(here.layer, near)
                            w.people[.noah]?.position = at
                        }
                        walk(to: stand)
                        steps(2)
                        return
                    }
                }
            }
        }
    }

    // MARK: 内容から引く

    struct Picks {
        let stoke: InteractionID
        let fuel: ItemID
        let ember: InteractionID?
        let wreck: [InteractionID]
        let shelter: [StructureKindID]

        init(_ c: ContentDB) throws {
            func hearthOps(_ d: InteractionDef) -> [HearthEffectOp] {
                (d.effects ?? []).compactMap { if case .hearth(_, let op) = $0 { op } else { nil } }
            }
            func onHearth(_ d: InteractionDef) -> Bool {
                if case .structure(let k) = d.target { return c.structures[k]?.hearth != nil }
                return false
            }
            let defs = c.interactions.values.sorted { $0.id.rawValue < $1.id.rawValue }
            let stokeDef = try XCTUnwrap(defs.first { d in
                onHearth(d) && hearthOps(d).contains { if case .addFuel = $0 { true } else { false } } && d.cost?.first?.item != nil
            }, "火床に燃料を足す行為が無い")
            stoke = stokeDef.id
            fuel = stokeDef.cost!.first!.item!
            ember = defs.first { d in
                onHearth(d) && (d.cost ?? []).isEmpty
                    && hearthOps(d).contains { if case .ignite(nil, _, _) = $0 { true } else { false } }
            }?.id
            wreck = defs.filter { d in
                if case .poi(let k) = d.target { return k == "wreck.home" && hearthOps(d).isEmpty }
                return false
            }.map(\.id)
            let housing = c.base.housingTag ?? "housing"
            func total(_ s: StructureDef) -> Int { s.cost.reduce(0) { $0 + $1.quantity } }
            shelter = c.structures.values.filter { ($0.provides[housing] ?? 0) > 0 && $0.hearth == nil && $0.requiresBaseArea != false }
                .sorted { (total($0), $0.id.rawValue) < (total($1), $1.id.rawValue) }
                .map(\.id)
        }

        /// その品を産む地形の行為(費用なし・短い順。開いているかは足元カードが見る)。
        static func gather(_ item: ItemID, _ c: ContentDB) -> InteractionDef? {
            c.interactions.values.filter { d in
                guard case .terrain = d.target, (d.cost ?? []).isEmpty else { return false }
                return d.yields.contains { $0.item == item }
            }.min { ($0.seconds, $0.id.rawValue) < ($1.seconds, $1.id.rawValue) }
        }
    }

    /// 場面を始める出来事か(定義の scene か、効果の startScene)。
    static func hasScene(_ id: EventID, _ c: ContentDB) -> Bool {
        guard let e = c.events[id] else { return false }
        return e.scene != nil || e.effects.contains { if case .startScene = $0 { true } else { false } }
    }

    // MARK: 1 走

    struct Run {
        var log: [(EventID, Double)] = []
        var ok: [String: Bool] = [:]
        var diag: [String] = []
        var fireAtDawn = false
        var shelterScene: EventID?
    }

    func run(seed: UInt64, content: ContentDB, picks: Picks, stack: Bool) -> Run {
        var b = Bot(content: content, seed: seed)
        var out = Run()
        let fireTag = content.base.constructionFireTag
        func fireLit() -> Bool { fireTag.map { BaseRules.total($0, b.w, content) > 0 } ?? true }
        func gather(_ item: ItemID, radius: Int = 24) -> Bool {
            guard let g = Picks.gather(item, content) else { out.diag.append("\(item.rawValue) を産む行為が無い"); return false }
            if b.act(g.id, radius: radius) { return true }
            if case .terrain(let tag) = g.target, b.rejects[g.id.rawValue] == "無い" {
                b.discover(tag: tag)
                return b.act(g.id, radius: 12)
            }
            return false
        }

        b.lightFire()
        // くべて最初の仲間を起こす
        var k = 0
        while b.members.count < 2 && k < 12 {
            if b.count(picks.fuel) == 0 { _ = gather(picks.fuel) }
            b.act(picks.stoke)
            b.readScenes()
            k += 1
        }
        out.ok["くべて 1 人目"] = b.members.count >= 2
        // 残骸への行為を一通り
        for id in picks.wreck {
            b.act(id)
            b.readScenes()
        }
        out.ok["残骸の後 4 人"] = b.members.count >= 4
        // 日没まで燃料を集め、日没の前に火のそばへ戻る
        k = 0
        while b.w.clock.phase == .day && k < 400 {
            if b.toDusk < 1800 {
                b.goHome()
                b.steps(10)
            } else if b.count(picks.fuel) >= 10 || !gather(picks.fuel) {
                b.steps(10)
            }
            b.readScenes()
            k += 1
        }
        let duskReal = b.real  // 夜の間は実時間の目安が進まない(寝る 30 秒だけ足す)
        b.steps(2)
        out.ok["日没で 5 人"] = b.members.count >= 5
        // 番(最後に加わった仲間)と夜作業
        if let fire = b.campfire(), let tender = b.members.last, tender != .noah {
            if stack, b.count(picks.fuel) > 0 {
                let r = b.sim.apply(.base(.hearth(placement: fire, op: .stack(item: picks.fuel, count: b.count(picks.fuel)))), to: &b.w)
                out.diag.append("積む: \(r.rejection?.reason.rawValue ?? "積んだ")")
            }
            let r = b.sim.apply(.crew(.assign(person: tender, assignment: .tendHearth(placement: fire))), to: &b.w)
            out.diag.append("火の番: \(r.rejection?.reason.rawValue ?? "受けた") 燃料 \(b.count(picks.fuel))")
        }
        _ = b.sim.apply(.time(.startNightWork), to: &b.w)
        b.steps(4)
        _ = b.sim.apply(.time(.sleep), to: &b.w)
        b.real += 30
        var n = 0
        while b.w.clock.phase != .day && n < 20000 {
            b.steps(1)
            n += 1
        }
        b.steps(2)
        let nightScenes = b.log.filter { $0.1 >= duskReal && Self.hasScene($0.0, content) }.map(\.0)
        out.ok["夜明け"] = b.w.clock.day >= 1
        out.ok["夜の場面"] = !nightScenes.isEmpty
        out.fireAtDawn = fireLit()
        out.diag.append("夜明けの火 \(out.fireAtDawn) 燃料 \(b.count(picks.fuel))")
        // 頼み: 2 人目に燃料、3 人目に水
        if b.members.count >= 3, let g = Picks.gather(picks.fuel, content), let a = b.find(g.id, radius: 24) {
            _ = b.sim.apply(.crew(.assign(person: b.members[1], assignment: .gather(interaction: a.id, at: a.at))), to: &b.w)
        }
        if b.members.count >= 3, let a = b.find("interaction.draw_water", radius: 30) {
            _ = b.sim.apply(.crew(.assign(person: b.members[2], assignment: .gather(interaction: a.id, at: a.at))), to: &b.w)
        }
        b.steps(4)
        // シェルター: 材料を集めて、拠点の範囲の中で焚き火に近い順に置く
        var placed: StructureKindID?
        var placedAt = 0
        for kind in picks.shelter where placed == nil {
            guard let def = content.structures[kind] else { continue }
            func short() -> [Ingredient] { def.cost.filter { i in i.item.map { b.count($0) < i.quantity } ?? false } }
            k = 0
            while !short().isEmpty && k < 60 {
                var did = false
                for ing in short() {
                    if ing.item == picks.fuel { b.goHome() }
                    did = gather(ing.item!, radius: 40) || did
                }
                if !did { b.steps(10) }
                k += 1
            }
            b.goHome()
            let fireAt = b.campfire().flatMap { b.w.placements.items[$0]?.at.point } ?? b.w.map.spawn.point
            guard let area = b.w.base.area else { out.diag.append("拠点の範囲が無い"); break }
            var cells: [GridPoint] = []
            for y in area.origin.y..<(area.origin.y + area.size.height) {
                for x in area.origin.x..<(area.origin.x + area.size.width) { cells.append(GridPoint(x, y)) }
            }
            cells.sort { max(abs($0.x - fireAt.x), abs($0.y - fireAt.y)) < max(abs($1.x - fireAt.x), abs($1.y - fireAt.y)) }
            var lastReject = "-"
            for c in cells.dropFirst() where placed == nil {
                let r = b.sim.apply(.base(.build(structure: kind, at: WorldPoint(.surface, c), facing: .south)), to: &b.w)
                if let j = r.rejection {
                    lastReject = j.reason.rawValue
                    if lastReject == "reason.base.missing_cost" || lastReject.hasSuffix("locked") { break }
                } else {
                    placed = kind
                    placedAt = b.log.count
                }
            }
            if placed == nil {
                let have = def.cost.compactMap { i in i.item.map { "\($0.rawValue) \(b.count($0))/\(i.quantity)" } }
                out.diag.append("\(kind.rawValue) を置けない: \(lastReject) 材料 \(have) 断り \(b.rejects.sorted { $0.key < $1.key })")
            }
        }
        out.ok["シェルターを置けた"] = placed != nil
        if let kind = placed,
           let s = b.w.placements.sortedIDs.first(where: { b.w.placements.items[$0]?.kind == .structure(kind) }) {
            // 建設は火が燃えている間だけ進む(W-02c)。消えていれば残り火から点け、燃料をくべてから建てる
            if !fireLit(), let e = picks.ember {
                b.goHome()
                out.diag.append("建てる前に火が消えていた(残り火から \(b.act(e) ? "点けた" : "点けられない"))")
            }
            for _ in 0..<3 {
                if b.count(picks.fuel) == 0 { _ = gather(picks.fuel, radius: 40) }
                b.goHome()
                b.act(picks.stoke)
            }
            b.goHome()
            // 手が先(INV-O8): ノアが自分で建てはじめてから、仲間に頼む
            _ = b.sim.apply(.crew(.assign(person: .noah, assignment: .build(placement: s))), to: &b.w)
            b.steps(20)
            for p in b.members.dropFirst() {
                _ = b.sim.apply(.crew(.assign(person: p, assignment: .build(placement: s))), to: &b.w)
            }
            n = 0
            // 日が暮れたら寝て、次の日に続きを建てる
            while b.w.placements.items[s]?.status != .running && n < 12000 {
                if b.w.clock.phase == .dusk || b.w.clock.phase == .nightWork, !b.w.clock.sleeping {
                    _ = b.sim.apply(.time(.sleep), to: &b.w)
                    b.real += 30
                }
                b.steps(1)
                n += 1
            }
            b.steps(8)
            let built = b.w.placements.items[s]?.status == .running
            out.ok["シェルターが建った"] = built
            out.shelterScene = b.log[placedAt...].map(\.0).first { Self.hasScene($0, content) }
            out.ok["建った後の場面"] = out.shelterScene != nil
            if !built { out.diag.append("建たない: \(String(describing: b.w.placements.items[s]!.status)) 火 \(fireLit())") }
        }
        out.log = b.log
        return out
    }

    func testFirstTenMinutesTimeline() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        var content = try TestContent.full()
        content.failureRules = [:]
        let picks = try Picks(content)
        XCTAssertFalse(picks.shelter.isEmpty, "寝床のある建造物が無い")
        let env = ProcessInfo.processInfo.environment
        let seeds = Int(env["REFORGE_TENMIN_SEEDS"] ?? "") ?? 5
        let stack = env["REFORGE_TENMIN_STACK"] == "1"
        var failed: [String: Int] = [:]
        var fireAtDawn = 0
        var shelterAt: [Int] = []
        var worstGap = 0.0
        // INV-S3: 応え(場面を始める出来事)と応えの間。600 秒までの間のうち 90 秒を超えるものを、前後の出来事の組で数える
        var longGaps: [String: [Int]] = [:]
        var gapStarts: [String: [Int]] = [:]
        var seedsOver = 0
        var worstAnswerGap = 0
        for seed in 0..<UInt64(seeds) {
            let r = run(seed: seed, content: content, picks: picks, stack: stack)
            for (k, v) in r.ok where !v { failed[k, default: 0] += 1 }
            if r.fireAtDawn { fireAtDawn += 1 }
            if let id = r.shelterScene, let t = r.log.first(where: { $0.0 == id })?.1 { shelterAt.append(Int(t)) }
            let times = r.log.map(\.1).filter { $0 <= 600 }
            worstGap = max(worstGap, zip(times, times.dropFirst()).map { $1 - $0 }.max() ?? 0)
            let answers = r.log.filter { $0.1 <= 600 && Self.hasScene($0.0, content) }
            var over = false
            for (a, b) in zip(answers, answers.dropFirst()) {
                let gap = Int(b.1 - a.1)
                worstAnswerGap = max(worstAnswerGap, gap)
                if gap > 90 {
                    let key = "\(a.0.rawValue) → \(b.0.rawValue)"
                    longGaps[key, default: []].append(gap)
                    gapStarts[key, default: []].append(Int(a.1))
                    over = true
                }
            }
            if over { seedsOver += 1 }
            if seed == 0 {
                print("[SL-40] seed 0 応え: " + answers.map { "\($0.0.rawValue)@\(Int($0.1))s" }.joined(separator: " "))
            }
            if seed < 2 || r.ok.values.contains(false) {
                print("[SL-40] seed \(seed): " + r.log.map { "\($0.0.rawValue)@\(Int($0.1))s" }.joined(separator: " "))
                print("[SL-40] seed \(seed) 段: \(r.ok.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
                print("[SL-40] seed \(seed) 診断: \(r.diag.joined(separator: " / "))")
            }
        }
        shelterAt.sort()
        let med = shelterAt.isEmpty ? -1 : shelterAt[shelterAt.count / 2]
        print("[SL-40] \(seeds) seed(山へ積む \(stack)): 夜明けに火が残った \(fireAtDawn) / 建った後の場面 \(shelterAt.count) 走"
            + "(中央 \(med) 秒・最長 \(shelterAt.last ?? -1) 秒)/ 出来事の間のいちばん長い所 \(Int(worstGap)) 秒(600 秒まで)")
        print("[INV-S3] \(seeds) seed: 応えの間が 90 秒を超えた seed \(seedsOver) / いちばん長い間 \(worstAnswerGap) 秒")
        for (k, v) in longGaps.sorted(by: { $0.value.count > $1.value.count }).prefix(12) {
            let g = v.sorted()
            let st = (gapStarts[k] ?? []).sorted()
            print("[INV-S3]   \(k): \(v.count) seed(間 中央 \(g[g.count / 2]) 秒・最長 \(g.last!) 秒。始まり 中央 \(st[st.count / 2]) 秒)")
        }
        print("[SL-40] \(seeds) seed: 届かなかった段 \(failed.sorted { $0.key < $1.key })")
        XCTAssertEqual(failed, [:], "届かなかった段がある")
    }
}
