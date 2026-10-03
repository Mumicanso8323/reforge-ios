import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// 最初の 10 分の版 SL-40(担当 U14): ボットが始まりの火から最初のシェルター、夜の石槌、岩山、炉、最初の鉄(SL-27)まで
/// 通しで遊び、出来事の時刻を並べる。非公開の層があり、REFORGE_TENMIN_BOT=1 の時だけ回す。
/// testResponsesVary は、同じ seed の途中の写しから 1 つだけ変えて、応えが変わるかを見る(SL-11・SL-18・SL-21・SL-22・SL-26)。
///
/// - 道具 = 鉱脈への行為が持てと言う品。炉 = furnace。炭 = 費用なしで炭を産む POI の行為。どれも内容から引く。
/// - REFORGE_TENMIN_UNTEND=1: 夜明けに火の番を外す(W-26 の番が昼に蓄えから山へ移す分を見分ける)。
///   REFORGE_TENMIN_NAMES: 名乗りの監査をする seed の数(既定 2)。REFORGE_TENMIN_VARY_SEEDS: 応えの変化の seed の数(既定 3)。
///
/// - 時刻は「実時間の目安」: 昼はゲームの 160 秒 = 実時間 1 秒。保留の間は押した秒数。場面を送るタップは 3〜4 秒。
/// - 行為・人・建造物は内容から引く(このテストは内容の ID を持たない)。
///   くべる = 焚き火に燃料を足す効果を持つ行為。残り火 = 確率なし・費用なしで点ける行為。
///   採る = その品を産む地形の行為(費用なし・短い順)。残骸 = 自分たちの残骸(wreck.home)への行為。
///   シェルター = 寝床(housing)を持つ建造物のうち費用の少ない順。番 = 最後に加わった仲間。
/// - 行為は足元カードから押す。カードは手の届くマスの行為だけを、ページに分けて出すので、候補のマスに立った形で全ページを見る。
/// - 歩くのは、行為の場所へは時間を進めて移す(1 秒 4 マス)。地形を見つけに行くときは最後を本物の歩く命令で(着いた時の解禁のため)。
/// - REFORGE_TENMIN_SEEDS: seed の数(既定 5)。REFORGE_TENMIN_SEED_FROM: 最初の seed(既定 0)。REFORGE_TENMIN_STACK=1: 夜の前に火床の薪の山へ積む(本体の .stack を直接送る)。
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
        /// 場面のほかの応え(INV-S3): 人の一言(line:)と、仲間が働きはじめた時の頭上の作業の字(work:)。
        var answers: [(String, Double)] = []
        /// 名乗る前の名前の監査(SL-30・TEST-F9): (人, 本当の名前, 名乗りの事実)。空なら監査しない
        var nameAudit: [(PersonID, String, FactID)] = []
        /// 見つかった食い違い(最初の 20 件)
        var leaks: [String] = []
        /// 頼まれてまだ働きはじめていない仲間(頼みのあと最初の作業の字だけを応えに数える)。
        var awaiting: Set<PersonID> = []
        /// 場面の行を聞き取る(応えの変化のテスト)。true の間、画面に出た場面の行を (場面, 行) で順に貯める
        var listen = false
        var heard: [(SceneID, String)] = []
        /// 足元カードが間を置いているマスで断られた回数・産む行為が無かった物(診断)
        var cooldownHits = 0
        var noSource: Set<String> = []
        var gatherMiss: [String: String] = [:]

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
            auditNames()
            for id in w.narrative.fired.keys.sorted(by: { $0.rawValue < $1.rawValue }) where !seen.contains(id) {
                seen.insert(id)
                log.append((id, real))
            }
        }

        /// 画面に渡る文字列(地図の人の印・場面・パネル)に、名乗る前の名前が出ていないか。
        mutating func auditNames() {
            guard !nameAudit.isEmpty, leaks.count < 20 else { return }
            let pending = nameAudit.filter { w.knowledge.facts[$0.2] == nil }
            guard !pending.isEmpty else { return }
            let strings = FrameText.allStrings(fb.build(w, revision: 0, previous: nil, report: nil))
            for (pid, name, fact) in pending {
                for s in strings where s.contains(name) {
                    let at = w.narrative.scene.map { "\($0.scene.rawValue)#\($0.line)" } ?? "-"
                    leaks.append("\(Int(real))s \(pid.rawValue)(\(fact.rawValue) 未知)場面 \(at): 「\(s.prefix(40))」")
                    if leaks.count >= 20 { return }
                    break
                }
            }
        }

        /// コマンドを送り、その中で言われた一言も記録する。
        @discardableResult
        mutating func send(_ c: Command) -> StepReport {
            let r = sim.apply(c, to: &w)
            record(r)
            auditNames()
            hear()
            if case .crew(.assign(let p, _)) = c, p != .noah, r.rejection == nil { awaiting.insert(p) }
            return r
        }

        mutating func record(_ r: StepReport) {
            for e in r.events {
                if case .lineSpoken(_, let line) = e { answers.append(("line:\(line.rawValue)", real)) }
            }
        }

        mutating func hear() {
            guard listen, let s = w.narrative.scene?.scene else { return }
            // ふきだしの場面は sceneLines、全画面の場面(stage)は prologue の行に出る
            let f = fb.build(w, revision: 0, previous: nil, report: nil)
            let shown = f.prologue?.kind == .stage ? (f.prologue?.lines ?? []) : f.sceneLines
            for l in shown where !heard.contains(where: { $0.0 == s && $0.1 == l }) {
                heard.append((s, l))
            }
        }

        /// その物を産む採取を 1 回する。足元カードは間を置いているマスにも行為を出す(押すと cooldown で断られる)ので、
        /// 断られたら別のマスを探し直し、見えている所に無ければ、まだ採っていない次のマスへ行く。
        mutating func gather(_ item: ItemID, radius: Int = 24) -> Bool {
            guard let g = Picks.gather(item, content) else { noSource.insert(item.rawValue); return false }
            for _ in 0..<12 {
                if act(g.id, radius: radius) { return true }
                guard rejects[g.id.rawValue] == "reason.explore.cooldown" else { break }
                cooldownHits += 1
            }
            if case .terrain(let tag) = g.target {
                discover(tag: tag, radius: max(48, radius * 2), avoid: spent)
                if act(g.id, radius: 12) { return true }
                var open = g.when.map { ConditionEvaluator.evaluatePure($0, world: w, content: content) == true } ?? true
                if !open {
                    // 探索の出来事で開く行為(岩場・川の新しい区域に入った時)。まだ入っていない区域を回る
                    if visitRegions(tag: tag, until: { b in b.act(g.id, radius: 6) }) { return true }
                    open = g.when.map { ConditionEvaluator.evaluatePure($0, world: w, content: content) == true } ?? true
                }
                let layer = w.map[here.layer]
                var d: Int?
                for dy in -12...12 {
                    for dx in -12...12 {
                        let q = GridPoint(here.point.x + dx, here.point.y + dy)
                        if let t = layer?.terrain(at: q), (content.terrains[t]?.tags ?? [t.rawValue]).contains(tag) {
                            d = min(d ?? 99, max(abs(dx), abs(dy)))
                        }
                    }
                }
                gatherMiss["\(g.id.rawValue)"] = "開いている \(open)・ノアから\(tag)まで \(d.map(String.init) ?? "12 超")"
            }
            return false
        }

        /// その札の地形がある 8×8 の区域を、近い順に 10 まで回る(探索の出来事は新しい区域に入った時に起きる)。
        /// done が true を返したら止める。
        mutating func visitRegions(tag: String, until done: (inout Bot) -> Bool) -> Bool {
            guard let layer = w.map[here.layer] else { return false }
            let c0 = here.point
            var cand: [GridPoint] = []
            for dy in -40...40 {
                for dx in -40...40 {
                    let q = GridPoint(c0.x + dx, c0.y + dy)
                    if let t = layer.terrain(at: q), (content.terrains[t]?.tags ?? [t.rawValue]).contains(tag) { cand.append(q) }
                }
            }
            cand.sort { $0.chebyshev(to: c0) < $1.chebyshev(to: c0) }
            var tried: Set<GridPoint> = []
            for q in cand where !tried.contains(GridPoint(q.x / 8, q.y / 8)) && tried.count < 10 {
                tried.insert(GridPoint(q.x / 8, q.y / 8))
                approach(q)
                if done(&self) { return true }
            }
            return false
        }

        /// 頼まれた仲間が働きはじめた(頭上に作業の字が出た)時を記録する。
        mutating func noteWork() {
            for id in awaiting.sorted(by: { $0.rawValue < $1.rawValue }) {
                switch w.people[id]?.activity {
                case .working, .interacting, .carrying:
                    awaiting.remove(id)
                    answers.append(("work:\(id.rawValue)", real))
                default:
                    break
                }
            }
        }

        mutating func steps(_ n: Int) {
            for _ in 0..<n {
                let r = sim.runSteps(1, &w)
                if w.clock.phase == .day { real += Self.realPerStep }
                note()
                record(r)
                noteWork()
                hear()
            }
        }

        /// 序を送り、暗い場面の行為を押し切る。
        mutating func lightFire() {
            var n = 0
            while w.narrative.scene != nil && n < 30 { _ = send(.narrative(.advanceScene)); n += 1; real += 4 }
            guard let act = fb.build(w, revision: 0, previous: nil, report: nil).darkStart?.action else { return }
            _ = send(act.start)
            var carry: Int64 = 0
            n = 0
            while w.clock.held && n < 20000 { record(sim.advanceHeld(&w, realSeconds: 0.1, carry: &carry)); n += 1; real += 0.1 }
            _ = send(act.end)
            note()
        }

        /// 足元カードの行為はページに分かれる(FootCard.maxActions ずつ)。全部のページから探す
        static func cardAction(_ fb: FrameBuilder, _ w: WorldState, at g: GridPoint, _ id: InteractionID) -> FootCard.Action? {
            guard let first = fb.footCard(w, at: g) else { return nil }
            if let a = first.actions.first(where: { $0.id == id }) { return a }
            for page in stride(from: 1, to: first.pageCount, by: 1) {
                if let a = fb.footCard(w, at: g, page: page)?.actions.first(where: { $0.id == id }) { return a }
            }
            return nil
        }

        /// ノアの近くで行為 id を探す(足元カードの行為)。近い順。
        /// 足元カードは手の届くマス(Reach)の行為しか出さないので、候補のマスごとに「ノアがそこに立った」形で見る。
        func find(_ id: InteractionID, radius: Int = 12) -> FootCard.Action? {
            let c = here.point
            let def = content.interactions[id]
            let cooling = def?.cooldownDays != nil
            let layer = w.map[here.layer]
            var probe = w
            for r in 0...radius {
                for dy in -r...r {
                    for dx in -r...r where max(abs(dx), abs(dy)) == r {
                        let g = c + GridPoint(dx, dy)
                        if cooling, spent.contains(g) { continue }
                        if case .terrain(let tag)? = def?.target {
                            guard let t = layer?.terrain(at: g), (content.terrains[t]?.tags ?? [t.rawValue]).contains(tag) else { continue }
                        }
                        let at = WorldPoint(here.layer, g)
                        probe.people[.noah]?.position = at
                        if let a = Self.cardAction(fb, probe, at: g, id) { return a }
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
            let r = send(a.start)
            guard r.rejection == nil else { rejects[id.rawValue] = r.rejection!.reason.rawValue; return false }
            var n = 0
            while w.exploration.active[.noah] != nil && n < 2000 { steps(1); n += 1 }
            _ = send(a.end)
            note()
            return true
        }

        /// 全画面の場面はタップで送る(ふきだしは時間で流れる)。
        mutating func readScenes() {
            var n = 0
            while let s = w.narrative.scene, content.scenes[s.scene]?.style.map({ "\($0)" }) == "stage", n < 20 {
                hear()
                _ = send(.narrative(.advanceScene))
                real += 3
                n += 1
            }
        }

        /// 日没までのゲーム秒(昼の間)。
        var toDusk: Int64 { Int64(content.clock.dayGameHours * 3600) - (w.clock.now - w.clock.dayStartedAt).seconds }

        /// 始まりの火の薪の山の数(burned は使わない。形を合わせるための 0)。
        func pileAndStock(_ fuel: ItemID) -> (pile: Int, burned: Int) {
            guard let f = campfire(), let p = w.placements.items[f], let s = Hearths.state(p, content) else { return (0, 0) }
            return (s.pile, 0)
        }

        /// 焚き火から、その品を産む地形のいちばん近いマスまでの距離(世界の側に材料が近くに無いかの診断)。
        func distanceToSource(_ item: ItemID) -> String {
            guard let g = Picks.gather(item, content), case .terrain(let tag) = g.target,
                  let f = campfire(), let c = w.placements.items[f]?.at.point, let layer = w.map[.surface] else { return "\(item.rawValue) ?" }
            var best: Int?
            for dy in -80...80 {
                for dx in -80...80 {
                    let q = GridPoint(c.x + dx, c.y + dy)
                    if let t = layer.terrain(at: q), (content.terrains[t]?.tags ?? [t.rawValue]).contains(tag) {
                        let d = max(abs(dx), abs(dy))
                        if best == nil || d < best! { best = d }
                    }
                }
            }
            return "\(item.rawValue) の\(tag)まで \(best.map(String.init) ?? "80 超")"
        }

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
            _ = send(.crew(.walk(to: to)))
            var m = 0
            while w.people[.noah]?.motion != nil && m < 2000 { steps(1); m += 1 }
        }

        /// その点のそばの歩けるマスへ行く(遠くは時間を進めて移り、最後を本物の歩く命令で)。
        mutating func approach(_ target: GridPoint) {
            guard let layer = w.map[here.layer] else { return }
            func passable(_ p: GridPoint) -> Bool {
                guard layer.size.contains(p), let t = layer.terrain(at: p), let d = content.terrains[t] else { return false }
                return d.passable != false && d.isWater != true
            }
            guard let stand = ([target] + target.neighbors8).first(where: passable) else { return }
            let c = here.point
            let near = stand + GridPoint(0, stand.y > c.y ? -3 : 3)
            if passable(near) {
                let d = max(abs(near.x - c.x), abs(near.y - c.y))
                steps(Int(Double(d) / 4 / Self.realPerStep))
                let at = WorldPoint(here.layer, near)
                w.people[.noah]?.position = at
            }
            walk(to: stand)
            steps(2)
        }

        /// その種類の POI の位置(近い順)。
        func pois(_ kind: POIKindID) -> [GridPoint] {
            let c = here.point
            return (w.map[here.layer]?.pois.values.filter { $0.kind == kind }.map(\.at) ?? [])
                .sorted { max(abs($0.x - c.x), abs($0.y - c.y)) < max(abs($1.x - c.x), abs($1.y - c.y)) }
        }

        /// その札の地形のいちばん近いマスのそばまで行く(遠くは時間を進めて移り、最後の数マスを歩く)。
        mutating func discover(tag: String, radius: Int = 48, avoid: Set<GridPoint> = []) {
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
                        guard has(p), !avoid.contains(p), let stand = p.neighbors8.first(where: { passable($0) && !has($0) }) ?? (passable(p) ? p : nil)
                        else { continue }
                        // 遠くは時間を進めて移し、最後の数マスを本物の歩く命令で(着いた時の解禁のため)。
                        // 歩けなかったら(道が無い・遠すぎる)、1 マス手前に移してからもう一度歩く
                        let offsets = [GridPoint(0, stand.y > c.y ? -3 : 3), GridPoint(stand.x > c.x ? -3 : 3, 0),
                                       GridPoint(0, stand.y > c.y ? 3 : -3), GridPoint(stand.x > c.x ? 3 : -3, 0)]
                        if let near = offsets.map({ stand + $0 }).first(where: passable) {
                            let d = max(abs(near.x - c.x), abs(near.y - c.y))
                            steps(Int(Double(d) / 4 / Self.realPerStep))
                            let at = WorldPoint(here.layer, near)
                            w.people[.noah]?.position = at
                        }
                        walk(to: stand)
                        if here.point != stand, let next = stand.neighbors8.first(where: { passable($0) && $0 != stand }) {
                            let at = WorldPoint(here.layer, next)
                            w.people[.noah]?.position = at
                            walk(to: stand)
                        }
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
        /// 最初の鉄まで(SL-23〜27): 手で掘る行為・その道具・道具を作る手作業と費用・炭を拾う行為と場所の種類
        let mine: InteractionID?
        let tool: ItemID?
        let toolWork: HandworkID?
        let toolCost: [(ItemID, Int)]
        let charcoalSource: (InteractionID, POIKindID)?

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
            func hasItems(_ cond: Condition?) -> [ItemID] {
                switch cond {
                case .has(let what)?: return what.item.map { [$0] } ?? []
                case .all(let xs)?: return xs.flatMap { hasItems($0) }
                default: return []
                }
            }
            let mineDef = defs.first { if case .deposit = $0.target { true } else { false } }
            mine = mineDef?.id
            let toolItem = hasItems(mineDef?.when).first
            tool = toolItem
            let workDef = c.handwork.values.sorted { $0.id.rawValue < $1.id.rawValue }
                .first { h in toolItem.map { t in (h.yields ?? []).contains { $0.item == t } } ?? false }
            toolWork = workDef?.id
            if case .array(let xs)? = workDef?.parameters?["cost"] {
                toolCost = xs.compactMap { v in
                    guard case .string(let i)? = v["item"], case .int(let q)? = v["quantity"] else { return nil }
                    return (ItemID(i), Int(q))
                }
            } else {
                toolCost = []
            }
            charcoalSource = defs.compactMap { d -> (InteractionID, POIKindID)? in
                guard case .poi(let k) = d.target, (d.cost ?? []).isEmpty, d.yields.contains(where: { $0.item == .charcoal })
                else { return nil }
                return (d.id, k)
            }.first
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

    // MARK: 応えの変化(SL-11・SL-18・SL-21・SL-22・SL-26)

    /// 置いた物の占めるマス。
    static func tiles(_ p: Placement) -> [GridPoint] {
        [p.at.point] + p.footprint.map { GridPoint(p.at.point.x + $0.x, p.at.point.y + $0.y) }
    }

    /// 占めるマスの間の最も近いチェビシェフ距離(nearPlacement と同じ測り方)。
    static func gap(_ a: [GridPoint], _ b: [GridPoint]) -> Int {
        a.flatMap { x in b.map { x.chebyshev(to: $0) } }.min() ?? Int.max
    }

    /// 占めるマスから r 以内に、その札の地形があるか。
    static func nearTag(_ ts: [GridPoint], _ tag: String, _ r: Int, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let layer = w.map[.surface] else { return false }
        for t in ts {
            for dy in -r...r {
                for dx in -r...r {
                    if let k = layer.terrain(at: GridPoint(t.x + dx, t.y + dy)),
                       (c.terrains[k]?.tags ?? [k.rawValue]).contains(tag) { return true }
                }
            }
        }
        return false
    }

    /// 水が近いとみなす距離(SL-22。game-designer 10/3 に 3 → 4)。
    static let waterRadius = 4

    /// 置き場の形: 火からの距離と、水から waterRadius 以内か。
    struct Spot: Equatable {
        var fire: Int
        var water: Bool
        var label: String { "火から \(fire)・水 \(water ? "\(FirstTenMinutesBotTests.waterRadius) 以内" : "遠い")" }
    }

    /// cells を順に試し、条件 want に合う置き場に置く(置けたら新しい置いた物の ID と置き場の形)。合わない置き方は捨てる。
    static func placeWhere(_ b: inout Bot, _ cells: [GridPoint], waterTag: String, want: (Spot) -> Bool,
                           place: (WorldPoint) -> Command) -> (EntityID, Spot)? {
        guard let f = b.campfire(), let fire = b.w.placements.items[f] else { return nil }
        let fireTiles = tiles(fire)
        let base = b
        for c in cells {
            var t = base
            let before = Set(t.w.placements.items.keys)
            guard t.send(place(WorldPoint(.surface, c))).rejection == nil,
                  let id = t.w.placements.sortedIDs.first(where: { !before.contains($0) }),
                  let pl = t.w.placements.items[id] else { continue }
            let ts = tiles(pl)
            let spot = Spot(fire: gap(ts, fireTiles), water: nearTag(ts, waterTag, Self.waterRadius, t.w, t.content))
            if want(spot) {
                b = t
                return (id, spot)
            }
        }
        return nil
    }

    /// 焚き火の周り(半径 10)のマスを近い順に。
    static func cellsAroundFire(_ b: Bot) -> [GridPoint] {
        guard let f = b.campfire(), let p = b.w.placements.items[f]?.at.point else { return [] }
        var out: [GridPoint] = []
        for dy in -10...10 {
            for dx in -10...10 where dx != 0 || dy != 0 { out.append(GridPoint(p.x + dx, p.y + dy)) }
        }
        return out.sorted { max(abs($0.x - p.x), abs($0.y - p.y)) < max(abs($1.x - p.x), abs($1.y - p.y)) }
    }

    /// 流れている場面を終わりまで流す(全画面の場面は送り、ふきだしの場面は時間で進むのを待つ)。
    static func playOut(_ b: inout Bot) {
        var n = 0
        while b.w.narrative.scene != nil && n < 400 {
            b.readScenes()
            b.steps(1)
            n += 1
        }
    }

    /// 聞き取った行のうち、mark より後に始まった最初の場面の行。
    static func firstScene(_ b: Bot, after mark: Int) -> (SceneID, [String])? {
        guard let s = b.heard.dropFirst(mark).first?.0 else { return nil }
        return (s, b.heard.dropFirst(mark).filter { $0.0 == s }.map(\.1))
    }

    /// 応えが、ノアのしたこと・置き場・頼み方で変わる(10 分の版 SL-11・SL-18・SL-21・SL-22・SL-26)。
    /// 同じ seed の途中の写しから、1 つだけ変えて比べる。行は画面に出た場面の行(sceneLines)と、頼みの返事の行の ID。
    func testResponsesVary() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REFORGE_TENMIN_BOT"] == "1",
                          "REFORGE_TENMIN_BOT=1 の時だけ回す(10 分の内容が入った層で)")
        setvbuf(stdout, nil, _IOLBF, 0)
        var content = try TestContent.full()
        content.failureRules = [:]
        let picks = try Picks(content)
        let seeds = Int(ProcessInfo.processInfo.environment["REFORGE_TENMIN_VARY_SEEDS"] ?? "") ?? 3
        let waterTag: String = {
            if case .terrain(let t)? = content.interactions["interaction.draw_water"]?.target { return t }
            return "shore"
        }()
        var problems: [String] = []
        for seed in 0..<UInt64(seeds) {
            let r = run(seed: seed, content: content, picks: picks, stack: false, snapshots: true)

            // SL-11: 手持ちの枝 3 本以上・火を盛んにした・何もせず待った の 3 回で、最初の仲間が加わる場面の一言が 3 回とも違う
            if let snap = r.snaps["SL-11"] {
                var got: [String: [String]] = [:]
                for how in ["枝", "火", "待つ"] {
                    var b = snap
                    b.listen = true
                    let m0 = b.members.count
                    var mark = 0
                    var k = 0
                    while b.members.count <= m0 && k < 300 {
                        mark = b.heard.count
                        switch how {
                        case "枝":
                            if b.count(picks.fuel) < 3 { _ = b.gather(picks.fuel) } else { b.steps(4) }
                        case "火":
                            if b.count(picks.fuel) == 0 { _ = b.gather(picks.fuel) }
                            b.goHome()
                            b.act(picks.stoke)
                        default:
                            b.steps(4)
                        }
                        k += 1
                    }
                    b.steps(2)
                    Self.playOut(&b)
                    let lines = Self.firstScene(b, after: mark)
                    got[how] = lines?.1 ?? []
                    print("[SL-11] seed \(seed) \(how): 加わった \(b.members.count > m0)・\(Int(b.real))s・場面 \(lines?.0.rawValue ?? "-") 行 \(lines?.1.count ?? 0)")
                }
                let vals = got.sorted { $0.key < $1.key }.map(\.value)
                if Set(vals.map { $0.joined(separator: "\n") }).count < 3 || vals.contains(where: \.isEmpty) {
                    problems.append("SL-11 seed \(seed): 3 回の一言が 3 通りにならない")
                }
            }

            // SL-21: 同じ人への頼みで一言が 2 通り以上(何を・どこで を変える)。頼みの種類ごとの数も出す
            if var snap = r.snaps["SL-21"] {
                // 水を汲む行為はノアが水辺まで歩くと開き、手が先(INV-O8)なのでノアが 1 度汲んでから頼める
                if case .terrain(let tag)? = content.interactions["interaction.draw_water"]?.target { snap.discover(tag: tag) }
                snap.act("interaction.draw_water", radius: 30)
                snap.goHome()
                var asks: [(String, Assignment)] = []
                if let g = Picks.gather(picks.fuel, content) {
                    if let near = snap.find(g.id, radius: 8) { asks.append(("採る", .gather(interaction: near.id, at: near.at))) }
                    if case .terrain(let tag) = g.target {
                        var far = snap
                        let c = snap.here.point
                        var close: Set<GridPoint> = []
                        for dy in -7...7 { for dx in -7...7 { close.insert(GridPoint(c.x + dx, c.y + dy)) } }
                        far.discover(tag: tag, radius: 40, avoid: close.union(snap.spent))
                        if let a = far.find(g.id, radius: 6), a.at.point.chebyshev(to: c) >= 8 {
                            asks.append(("採る", .gather(interaction: a.id, at: a.at)))
                        }
                    }
                }
                var probe = snap
                probe.spent = []  // ノアが汲んだマスも、仲間には頼める
                if let a = probe.find("interaction.draw_water", radius: 30) { asks.append(("水", .gather(interaction: a.id, at: a.at))) }
                if let f = snap.campfire() { asks.append(("火の番", .tendHearth(placement: f))) }
                for p in snap.members where p != .noah {
                    var replies: [String: Set<String>] = [:]
                    var refused: Set<String> = []
                    for (kind, a) in asks {
                        // 1 度目と、いったん外してからの 2 度目
                        var b = snap
                        for again in 0..<2 {
                            if again == 1 {
                                b.send(.crew(.assign(person: p, assignment: .idle)))
                                b.steps(4)
                            }
                            let rep = b.send(.crew(.assign(person: p, assignment: a)))
                            if let j = rep.rejection { refused.insert("\(kind) \(j.reason.rawValue)") }
                            for e in rep.events {
                                if case .lineSpoken(let who, let line) = e, who == p { replies[kind, default: []].insert(line.rawValue) }
                            }
                        }
                    }
                    let all = replies.values.reduce(into: Set<String>()) { $0.formUnion($1) }
                    let per = replies.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.count)" }.joined(separator: "・")
                    let single = replies.filter { $0.value.count < 2 }.keys.sorted()
                    print("[SL-21] seed \(seed) \(p.rawValue): 返事 \(all.count) 通り(\(per))・1 通りだけの頼み \(single)・断り \(refused.sorted())・頼んだ種類 \(asks.map(\.0))・水の行為 \(probe.rejects["interaction.draw_water"] ?? "-")")
                    if all.count < 2 { problems.append("SL-21 seed \(seed) \(p.rawValue): 返事が 2 通りにならない(\(per))") }
                }
            }

            // SL-22: 火から 2・火から 5・水から 3 の 3 回で、建った時の 4 人の一言の組が 3 回とも違う
            if let snap = r.snaps["SL-22"], let kind = r.shelterKind, let area = snap.w.base.area {
                var cells: [GridPoint] = []
                for y in area.origin.y..<(area.origin.y + area.size.height) {
                    for x in area.origin.x..<(area.origin.x + area.size.width) { cells.append(GridPoint(x, y)) }
                }
                let wants: [(String, (Spot) -> Bool)] = [
                    ("火から 2", { $0.fire <= 2 && !$0.water }),
                    ("火から 4", { $0.fire >= 4 && !$0.water }),
                    ("水から 4", { $0.water && $0.fire == 3 }),  // 火から 4 以上だと「遠い」の言い換えが先に選ばれる
                ]
                var got: [String: [String]] = [:]
                for (name, want) in wants {
                    var b = snap
                    guard let (id, spot) = Self.placeWhere(&b, cells, waterTag: waterTag, want: want,
                                                           place: { .base(.build(structure: kind, at: $0, facing: .south)) }) else {
                        print("[SL-22] seed \(seed) \(name): 拠点の範囲に合うマスが無い")
                        continue
                    }
                    b.listen = true
                    if let e = picks.ember {
                        b.goHome()
                        b.act(e)
                    }
                    for _ in 0..<3 {
                        if b.count(picks.fuel) == 0 { _ = b.gather(picks.fuel, radius: 40) }
                        b.goHome()
                        b.act(picks.stoke)
                    }
                    b.goHome()
                    b.send(.crew(.assign(person: .noah, assignment: .build(placement: id))))
                    b.steps(20)
                    for p in b.members.dropFirst() { b.send(.crew(.assign(person: p, assignment: .build(placement: id)))) }
                    var mark = b.heard.count
                    var n = 0
                    while b.w.placements.items[id]?.status != .running && n < 12000 {
                        if b.w.clock.phase == .dusk || b.w.clock.phase == .nightWork, !b.w.clock.sleeping { b.send(.time(.sleep)) }
                        mark = b.heard.count
                        b.steps(1)
                        n += 1
                    }
                    b.steps(8)
                    Self.playOut(&b)
                    let lines = Self.firstScene(b, after: mark)
                    got[name] = lines?.1 ?? []
                    print("[SL-22] seed \(seed) \(name)(\(spot.label)): 場面 \(lines?.0.rawValue ?? "-") 行 \(lines?.1.count ?? 0)")
                }
                let vals = got.sorted { $0.key < $1.key }.map(\.value)
                if vals.count >= 2, Set(vals.map { $0.joined(separator: "\n") }).count < vals.count || vals.contains(where: \.isEmpty) {
                    problems.append("SL-22 seed \(seed): 置き場を変えても 4 人の一言の組が変わらない回がある(\(got.keys.sorted()))")
                }
            }

            // SL-26: 炉を置き場を変えて 2 回(火のそば/火からも水からも遠い)置くと、一言が違う
            if let snap = r.snaps["SL-26"] {
                let cells = Self.cellsAroundFire(snap)
                var got: [String: [String]] = [:]
                let wants: [(String, (Spot) -> Bool)] = [("火のそば", { $0.fire <= 2 && !$0.water }), ("遠い", { $0.fire >= 5 && !$0.water })]
                for (name, want) in wants {
                    var b = snap
                    b.listen = true
                    let mark = b.heard.count
                    guard let (_, spot) = Self.placeWhere(&b, cells, waterTag: waterTag, want: want,
                                                          place: { .production(.place(module: .furnace, at: $0, facing: .north)) }) else {
                        print("[SL-26] seed \(seed) \(name): 合うマスが無い")
                        continue
                    }
                    b.steps(8)
                    Self.playOut(&b)
                    let lines = Self.firstScene(b, after: mark)
                    got[name] = lines?.1 ?? []
                    print("[SL-26] seed \(seed) \(name)(\(spot.label)): 場面 \(lines?.0.rawValue ?? "-") 行 \(lines?.1.count ?? 0)")
                }
                let vals = got.sorted { $0.key < $1.key }.map(\.value)
                if vals.count == 2, vals[0] == vals[1] || vals.contains(where: \.isEmpty) {
                    problems.append("SL-26 seed \(seed): 置き場を変えても一言が同じ")
                }
            }

            // SL-18: 番を頼んだ夜と頼まない夜で、夜明けが違う(足跡の地図の印は本体の Frame 待ち。今は知った事実の差を見る)
            if let snap = r.snaps["SL-18"] {
                var facts: [Bool: Set<FactID>] = [:]
                var lit: [Bool: Bool] = [:]
                var maps: [Bool: [Int]] = [:]
                var dark: [Bool: Int] = [:]
                for tend in [true, false] {
                    var b = snap
                    if tend, let fire = b.campfire(), let tender = b.members.last, tender != .noah {
                        b.send(.crew(.assign(person: tender, assignment: .tendHearth(placement: fire))))
                    }
                    b.send(.time(.startNightWork))
                    b.steps(4)
                    b.send(.time(.sleep))
                    var n = 0
                    while b.w.clock.phase != .day && n < 20000 {
                        b.steps(1)
                        n += 1
                    }
                    b.steps(2)
                    facts[tend] = Set(b.w.knowledge.facts.keys)
                    lit[tend] = b.campfire().flatMap { b.w.placements.items[$0] }.flatMap { Hearths.state($0, content) }?.lit ?? false
                    maps[tend] = b.fb.build(b.w, revision: 0, previous: nil, report: nil).map.chunkSignatures
                    // 灯りの外でも見える置いた物(足跡など)が、昼の地図に出ている数
                    let frame = b.fb.build(b.w, revision: 0, previous: nil, report: nil)
                    dark[tend] = frame.placements.filter { sp in
                        guard case .structure(let k)? = b.w.placements.items[sp.id]?.kind else { return false }
                        return content.structures[k]?.seenInDark == true
                    }.count
                }
                let onlyUntended = (facts[false] ?? []).subtracting(facts[true] ?? [])
                print("[SL-18] seed \(seed): 夜明けの火 番あり \(lit[true] ?? false) / 番なし \(lit[false] ?? false)"
                      + "・番なしの夜だけ知った事実 \(onlyUntended.count)・地図のチャンクの署名が違う \(maps[true] != maps[false])"
                      + "・夜明けの地図の足跡の印 番あり \(dark[true] ?? 0) / 番なし \(dark[false] ?? 0)")
                if content.structures.values.contains(where: { $0.seenInDark == true }) {
                    if (dark[false] ?? 0) <= (dark[true] ?? 0) {
                        problems.append("SL-18 seed \(seed): 番を頼まない夜の明け方の地図に、足跡の印が増えていない")
                    }
                } else if onlyUntended.isEmpty {
                    problems.append("SL-18 seed \(seed): 番を頼まない夜だけの夜明けの印(事実)が無い")
                }
            }
        }
        for p in problems { print("[VARY] \(p)") }
        XCTAssertEqual(problems, [], "応えが変わらない所がある")
    }


    /// SL-22 の置き場(火から 2・火から 4 以上・水から 4 以内)が拠点の範囲に置けるか。3 通り全部が置けない seed は数えて出し、
    /// 2 通り以上置けない seed が無いことを確かめる(game-designer 10/3)。
    /// 置き場の形だけを見る(火を点けた直後の世界に、シェルターの材料と解禁を足して、建てる命令が通るかを試す)。
    /// シェルターの種類は seed 0 の通しの走りで置いた物。REFORGE_TENMIN_SPOT_SEEDS: seed の数(既定 1000)。
    func testShelterSpotsEverySeed() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REFORGE_TENMIN_BOT"] == "1",
                          "REFORGE_TENMIN_BOT=1 の時だけ回す(10 分の内容が入った層で)")
        setvbuf(stdout, nil, _IOLBF, 0)
        var content = try TestContent.full()
        content.failureRules = [:]
        let picks = try Picks(content)
        let seeds = Int(ProcessInfo.processInfo.environment["REFORGE_TENMIN_SPOT_SEEDS"] ?? "") ?? 1000
        let waterTag: String = {
            if case .terrain(let t)? = content.interactions["interaction.draw_water"]?.target { return t }
            return "shore"
        }()
        let first = run(seed: 0, content: content, picks: picks, stack: false, snapshots: true)
        let kind = try XCTUnwrap(first.shelterKind, "seed 0 でシェルターを置けなかった")
        let cost = content.structures[kind]?.cost ?? []
        let wants: [(String, (Spot) -> Bool)] = [
            ("火から 2", { $0.fire <= 2 && !$0.water }),
            ("火から 4 以上", { $0.fire >= 4 }),
            ("水から 4 以内", { $0.water }),
        ]
        var missing: [String: [UInt64]] = [:]
        var onlyOne: [UInt64] = []
        for seed in 0..<UInt64(seeds) {
            var b = Bot(content: content, seed: seed)
            b.lightFire()
            var n = 0
            while b.w.base.area == nil && n < 40 {
                b.steps(1)
                n += 1
            }
            guard let area = b.w.base.area else {
                missing["拠点の範囲が無い", default: []].append(seed)
                continue
            }
            var ctx = StepContext(world: b.w, content: content)
            for ing in cost {
                if let item = ing.item { ctx.addStock(.item(item), ing.quantity, to: .base) }
            }
            b.w = ctx.world
            b.w.research.unlocked.structures.insert(kind)
            var cells: [GridPoint] = []
            for y in area.origin.y..<(area.origin.y + area.size.height) {
                for x in area.origin.x..<(area.origin.x + area.size.width) { cells.append(GridPoint(x, y)) }
            }
            var ok = 0
            for (name, want) in wants {
                var t = b
                if Self.placeWhere(&t, cells, waterTag: waterTag, want: want,
                                   place: { .base(.build(structure: kind, at: $0, facing: .south)) }) == nil {
                    missing[name, default: []].append(seed)
                } else {
                    ok += 1
                }
            }
            if ok < 2 { onlyOne.append(seed) }
        }
        let bad = Set(missing.values.flatMap { $0 })
        print("[SL-22-spots] 2 通り以上置けない seed \(onlyOne.count)\(onlyOne.isEmpty ? "" : ": " + onlyOne.map(String.init).joined(separator: ","))")
        print("[SL-22-spots] \(seeds) seed: 3 通りとも置けた \(seeds - bad.count) / 置けない seed \(bad.count)"
              + missing.sorted { $0.key < $1.key }.map { "・\($0.key) \($0.value.count)" }.joined())
        for (k, v) in missing.sorted(by: { $0.key < $1.key }) {
            print("[SL-22-spots]   \(k): \(v.prefix(60).map(String.init).joined(separator: ","))\(v.count > 60 ? " ほか" : "")")
        }
        // game-designer 10/3: 3 通り全部は 972/1000 でよい。2 通り以上置けない seed が 0 であること
        XCTAssertEqual(onlyOne, [], "置き場が 1 通り以下しか置けない seed がある")
    }

    /// 一覧(10 分の版 §1)の目安の時刻(秒)。±30 秒を見る
    static let window: [String: (Int, Int)] = [
        "SL-23 道具": (380, 420), "SL-24 頼んだ": (420, 450), "SL-25 岩山": (450, 540), "SL-25 掘った": (450, 540),
        "SL-26 炉": (540, 540), "SL-27 熱": (600, 700), "SL-27 最初の鉄": (600, 700),
    ]

    /// 場面を始める出来事か(定義の scene か、効果の startScene)。
    static func hasScene(_ id: EventID, _ c: ContentDB) -> Bool {
        guard let e = c.events[id] else { return false }
        return e.scene != nil || e.effects.contains { if case .startScene = $0 { true } else { false } }
    }

    /// 名乗りで名前が開く人: 人の見え方の見出しのうち、場面の行が learns で教える事実を条件にした物(SL-30・TEST-F9)。
    /// 名前の語はコンテンツから引く(このテストは物語の語を持たない)。
    static func namedPeople(_ c: ContentDB) -> [(PersonID, String, FactID)] {
        let learned = Set(c.scenes.values.flatMap { $0.lines.flatMap { $0.learns ?? [] } })
        var out: [(PersonID, String, FactID)] = []
        for (sid, def) in c.perception.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where sid.rawValue.hasPrefix("person:") {
            let pid = PersonID(String(sid.rawValue.dropFirst("person:".count)))
            for v in def.variants {
                guard case .fact(let f) = v.when, learned.contains(f), let n = v.name, let text = c.texts[n], !text.isEmpty
                else { continue }
                out.append((pid, text, f))
            }
        }
        return out
    }

    // MARK: 1 走

    struct Run {
        var log: [(EventID, Double)] = []
        var ok: [String: Bool] = [:]
        var diag: [String] = []
        var fireAtDawn = false
        var shelterScene: EventID?
        var answers: [(String, Double)] = []
        /// シェルターの材料集め: 実時間の目安(秒)・60 回で詰まったか・その間に山へ移った燃料のおおよその数。
        var material: (seconds: Double, stuck: Bool, toPile: Int)?
        /// シェルターの材料集めの間(実時間の目安の始まりと終わり)。INV-S3 の長い間を「材料集め」と「それ以外」に分ける
        var materialWindow: (Double, Double)?
        var leaks: [String] = []
        /// SL-23〜27 の段と時刻(実時間の目安)
        var milestones: [(String, Double)] = []
        var stoppedAt: String?
        /// 応えの変化のテスト用の途中の写し(snapshots: true の時だけ)。SL-11 火の後・SL-18 日没・SL-21 夜明けの頼みの前・
        /// SL-22 シェルターを置く前(材料はそろっている)・SL-26 炉を置く前
        var snaps: [String: Bot] = [:]
        var shelterKind: StructureKindID?
    }

    func run(seed: UInt64, content: ContentDB, picks: Picks, stack: Bool,
             nameAudit: [(PersonID, String, FactID)] = [], snapshots: Bool = false) -> Run {
        var b = Bot(content: content, seed: seed)
        b.nameAudit = nameAudit
        var out = Run()
        let fireTag = content.base.constructionFireTag
        func fireLit() -> Bool { fireTag.map { BaseRules.total($0, b.w, content) > 0 } ?? true }
        func gather(_ item: ItemID, radius: Int = 24) -> Bool { b.gather(item, radius: radius) }

        b.lightFire()
        if snapshots { out.snaps["SL-11"] = b }
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
        if snapshots { out.snaps["SL-18"] = b }
        // 番(最後に加わった仲間)と夜作業
        if let fire = b.campfire(), let tender = b.members.last, tender != .noah {
            if stack, b.count(picks.fuel) > 0 {
                let r = b.send(.base(.hearth(placement: fire, op: .stack(item: picks.fuel, count: b.count(picks.fuel)))))
                out.diag.append("積む: \(r.rejection?.reason.rawValue ?? "積んだ")")
            }
            let r = b.send(.crew(.assign(person: tender, assignment: .tendHearth(placement: fire))))
            out.diag.append("火の番: \(r.rejection?.reason.rawValue ?? "受けた") 燃料 \(b.count(picks.fuel))")
        }
        _ = b.send(.time(.startNightWork))
        b.steps(4)
        b.readScenes()
        // 夜の目(灯りの外でも見える置いた物)は、灯り(視界)の外に置かれているか(SL-18)
        do {
            let f = b.fb.build(b.w, revision: 0, previous: nil, report: nil)
            let dark = f.placements.filter { sp in
                guard case .structure(let k)? = b.w.placements.items[sp.id]?.kind else { return false }
                return content.structures[k]?.seenInDark == true
            }
            if !dark.isEmpty {
                let inside = dark.filter { sp in f.map.vision.contains { $0.contains(sp.at) } }
                out.ok["夜の目が灯りの外"] = inside.isEmpty
                if !inside.isEmpty { out.diag.append("夜の目が灯りの中: \(inside.map(\.at))") }
            }
        }
        _ = b.send(.time(.sleep))
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
        out.diag.append("夜明けの火 \(out.fireAtDawn) 燃料 \(b.count(picks.fuel)) 山 \(b.pileAndStock(picks.fuel).pile) 炭 \(b.count(.charcoal))")
        if let g = Picks.gather(picks.fuel, content), case .terrain(let tag) = g.target, let f = b.campfire(),
           let fp = b.w.placements.items[f]?.at.point, let layer = b.w.map[.surface] {
            var tagged = 0, cooling = 0
            for dy in -20...20 {
                for dx in -20...20 {
                    let q = fp + GridPoint(dx, dy)
                    guard let t = layer.terrain(at: q), (content.terrains[t]?.tags ?? [t.rawValue]).contains(tag) else { continue }
                    tagged += 1
                    let key = ExplorationState.countKey(g.id, poi: nil, at: WorldPoint(.surface, q))
                    if let d = b.w.exploration.harvestedDay[key], b.w.clock.day - d < (g.cooldownDays ?? 0) { cooling += 1 }
                }
            }
            out.diag.append("夜明け: 焚き火から 20 マスの \(tag) \(tagged) マス・間を置いている \(cooling)")
        }
        // REFORGE_TENMIN_UNTEND=1: 夜明けに火の番を外す(番が昼も蓄えから山へ移し続けるかを見分ける)
        if ProcessInfo.processInfo.environment["REFORGE_TENMIN_UNTEND"] == "1", let tender = b.members.last, tender != .noah {
            b.send(.crew(.assign(person: tender, assignment: .idle)))
        }
        if snapshots { out.snaps["SL-21"] = b }
        // 頼み: 2 人目に燃料、3 人目に水
        if b.members.count >= 3, let g = Picks.gather(picks.fuel, content), let a = b.find(g.id, radius: 24) {
            _ = b.send(.crew(.assign(person: b.members[1], assignment: .gather(interaction: a.id, at: a.at))))
        }
        if b.members.count >= 3 {
            // 水を汲む行為は、ノアが水辺のそばまで歩くと開く(まだなら水辺まで歩いてから頼む)
            if b.find("interaction.draw_water", radius: 30) == nil,
               case .terrain(let tag)? = content.interactions["interaction.draw_water"]?.target {
                b.discover(tag: tag)
            }
            // 手が先(INV-O8): ノアが 1 度汲んでから頼む
            b.act("interaction.draw_water", radius: 8)
            var probe = b
            probe.spent = []
            if let a = probe.find("interaction.draw_water", radius: 30) {
                let r = b.send(.crew(.assign(person: b.members[2], assignment: .gather(interaction: a.id, at: a.at))))
                if let j = r.rejection { out.diag.append("水を頼めない: \(j.reason.rawValue)") }
            } else {
                out.diag.append("水を頼めない(行為が見つからない)")
            }
            b.goHome()
        }
        b.steps(4)
        // シェルター: 材料を集めて、拠点の範囲の中で焚き火に近い順に置く
        var placed: StructureKindID?
        var placedAt = 0
        for kind in picks.shelter where placed == nil {
            // 開いていない建造物は飛ばす(建てるコマンドが locked で断る物)
            guard let def = content.structures[kind], b.w.research.unlocked.structures.contains(kind) else { continue }
            func short() -> [Ingredient] { def.cost.filter { i in i.item.map { b.count($0) < i.quantity } ?? false } }
            k = 0
            let t0 = b.real
            let pile0 = b.pileAndStock(picks.fuel)
            while !short().isEmpty && k < 60 {
                var did = false
                for ing in short() {
                    if ing.item == picks.fuel { b.goHome() }
                    did = gather(ing.item!, radius: 40) || did
                }
                if !did { b.steps(10) }
                k += 1
            }
            // 材料集めの長さと、その間に火の番が蓄えから山へ移した燃料(W-26)。60 回で止まったら「詰まり」
            let pile1 = b.pileAndStock(picks.fuel)
            out.materialWindow = (t0, b.real)
            out.material = (b.real - t0, k >= 60, max(0, pile1.pile - pile0.pile) + max(0, pile0.burned - pile1.burned))
            out.diag.append("材料集めの間の山 \(pile0.pile)→\(pile1.pile)")
            b.goHome()
            if snapshots, short().isEmpty {
                out.snaps["SL-22"] = b
                out.shelterKind = kind
            }
            let fireAt = b.campfire().flatMap { b.w.placements.items[$0]?.at.point } ?? b.w.map.spawn.point
            guard let area = b.w.base.area else { out.diag.append("拠点の範囲が無い"); break }
            var cells: [GridPoint] = []
            for y in area.origin.y..<(area.origin.y + area.size.height) {
                for x in area.origin.x..<(area.origin.x + area.size.width) { cells.append(GridPoint(x, y)) }
            }
            cells.sort { max(abs($0.x - fireAt.x), abs($0.y - fireAt.y)) < max(abs($1.x - fireAt.x), abs($1.y - fireAt.y)) }
            var lastReject = "-"
            for c in cells.dropFirst() where placed == nil {
                let r = b.send(.base(.build(structure: kind, at: WorldPoint(.surface, c), facing: .south)))
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
                let far = def.cost.compactMap { i in i.item }.filter { b.count($0) == 0 }.map { b.distanceToSource($0) }
                out.diag.append("\(kind.rawValue) を置けない: \(lastReject) 材料 \(have) 無い物の元まで \(far) 断り \(b.rejects.sorted { $0.key < $1.key })")
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
            _ = b.send(.crew(.assign(person: .noah, assignment: .build(placement: s))))
            b.steps(20)
            for p in b.members.dropFirst() {
                _ = b.send(.crew(.assign(person: p, assignment: .build(placement: s))))
            }
            n = 0
            // 日が暮れたら寝て、次の日に続きを建てる
            while b.w.placements.items[s]?.status != .running && n < 12000 {
                if b.w.clock.phase == .dusk || b.w.clock.phase == .nightWork, !b.w.clock.sleeping {
                    _ = b.send(.time(.sleep))
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
        // ---------------- SL-23〜27: 夜の道具 → 粘土 → 岩山で手で掘る → 炉 → 炭 → 予熱 1100℃ → 試す → 最初の鉄
        iron: do {
            guard out.ok["シェルターが建った"] == true, let mineID = picks.mine else { break iron }
            func mark(_ name: String) { out.milestones.append((name, b.real)) }
            func stop(_ at: String) { out.stoppedAt = at }
            func has(_ item: ItemID) -> Bool {
                ConditionEvaluator.evaluatePure(.has(what: Ingredient(item: item, quantity: 1)), world: b.w, content: content) == true
            }
            // SL-23: 道具の材料を日のうちに集め、日没の夜作業の灯りの中で作る
            for (item, q) in picks.toolCost {
                var tries = 0
                while b.count(item) < q && tries < 20 {
                    if !gather(item, radius: 40) { b.steps(10) }
                    tries += 1
                }
            }
            b.goHome()
            n = 0
            while b.w.clock.phase == .day && n < 20000 {
                b.steps(1)
                n += 1
            }
            b.send(.time(.startNightWork))
            if let hw = picks.toolWork {
                let r = b.send(.production(.handwork(id: hw, input: nil, holding: true)))
                // 夜作業の手作業は押した回数ぶんの時間(1 回 = pressSeconds。昼の 160 倍で実時間に)を実時間に数える
                let def = content.handwork[hw]
                b.real += Double((def?.presses ?? 8) * (def?.pressSeconds ?? 160)) / 160
                if let j = r.rejection { out.diag.append("道具の手作業: \(j.reason.rawValue)") }
            }
            out.ok["夜の道具"] = picks.tool.map(has) ?? true
            guard out.ok["夜の道具"] == true else { stop("SL-23 道具"); break iron }
            mark("SL-23 道具")
            b.send(.time(.sleep))
            b.real += 30
            n = 0
            while b.w.clock.phase != .day && n < 20000 {
                b.steps(1)
                n += 1
            }
            b.steps(2)
            mark("SL-24 夜明け")
            // SL-24: 炉の材料のうち、手で 1 度採ってから仲間に頼む(石は岩山で)
            let furnaceKind: ModuleKindID = .furnace
            let furnaceCost = content.modules[furnaceKind]?.cost ?? []
            var crew = Array(b.members.dropFirst())
            var asked = 0
            for ing in furnaceCost {
                guard let item = ing.item, let g = Picks.gather(item, content) else { continue }
                if case .terrain(let tag) = g.target, tag == "rock" { continue }
                _ = gather(item, radius: 40)
                for _ in 0..<2 where !crew.isEmpty {
                    guard let a = b.find(g.id, radius: 20) else { break }
                    let p = crew.removeFirst()
                    if b.send(.crew(.assign(person: p, assignment: .gather(interaction: a.id, at: a.at)))).rejection == nil { asked += 1 }
                }
            }
            // 炭(炉の予熱 + 試す 1 段)は、残っている仲間 1 人に燃え跡を漁ってもらう
            if b.count(.charcoal) < 3, let (cid, kind) = picks.charcoalSource, let at = b.pois(kind).first, !crew.isEmpty {
                var probe = b
                probe.approach(at)
                if let a = probe.find(cid, radius: 6) {
                    let p = crew.removeFirst()
                    if b.send(.crew(.assign(person: p, assignment: .gather(interaction: a.id, at: a.at)))).rejection == nil { asked += 1 }
                }
            }
            mark("SL-24 頼んだ(\(asked) 人)")
            // SL-25: 岩山へ行き、手で掘る ×2
            if let lm = b.w.map.landmarks { b.approach(lm.outcrop) }
            mark("SL-25 岩山")
            var mined = 0
            for _ in 0..<2 {
                if b.act(mineID, radius: 8) {
                    mined += 1
                    continue
                }
                // 岩山の目印のそばに掘れる鉱脈が見えなければ、いちばん近い残りのある鉱脈へ行く
                let c = b.here.point
                let near = b.w.map[b.here.layer]?.deposits.all
                    .filter { $0.remainingExtractions > 0 }
                    .min { $0.position.chebyshev(to: c) < $1.position.chebyshev(to: c) }
                guard let d = near else { break }
                b.approach(d.position)
                if b.act(mineID, radius: 4) {
                    mined += 1
                    continue
                }
                // 手で掘るは、岩場の新しい区域に入った時の探索の出来事で開く。開いていなければ、まだ入っていない岩場の区域を回る
                if b.visitRegions(tag: "rock", until: { t in t.act(mineID, radius: 6) }) { mined += 1 }
                if mined == 0 { out.diag.append("手で掘る: 岩場の区域を回っても開かない") }
            }
            out.ok["手で掘った"] = mined > 0
            guard mined > 0 else { stop("SL-25 掘る(\(b.rejects[mineID.rawValue] ?? "-"))"); break iron }
            mark("SL-25 掘った")
            if let g = furnaceCost.compactMap({ $0.item }).compactMap({ Picks.gather($0, content) })
                .first(where: { if case .terrain(let t) = $0.target { t == "rock" } else { false } }) {
                for p in crew {
                    guard let a = b.find(g.id, radius: 12) else { break }
                    if b.send(.crew(.assign(person: p, assignment: .gather(interaction: a.id, at: a.at)))).rejection == nil { asked += 1 }
                }
            }
            // 炉の材料をそろえる(手でも採る)
            func shortF() -> [Ingredient] { furnaceCost.filter { i in i.item.map { b.count($0) < i.quantity } ?? false } }
            k = 0
            while !shortF().isEmpty && k < 80 {
                var did = false
                for ing in shortF() { did = gather(ing.item!, radius: 40) || did }
                if !did { b.steps(10) }
                k += 1
            }
            // 炭: 炭を拾える残骸へ(夜が近いと漁れないので、炉を置く前に)
            if b.count(.charcoal) < 3, let (cid, kind) = picks.charcoalSource, let at = b.pois(kind).first {
                b.approach(at)
                var t = 0
                while b.count(.charcoal) < 4 && t < 6 && b.act(cid, radius: 6) { t += 1 }
                out.diag.append("燃え跡を漁った \(t) 回")
                b.goHome()
            }
            let burnt = picks.charcoalSource.map { src in
                b.w.ledger.records.filter { r in r.act == .scavenged && !src.0.rawValue.isEmpty }.count
            } ?? -1
            out.diag.append("炭 \(b.count(.charcoal))・漁った記録 \(burnt)・燃え跡の断り \(picks.charcoalSource.flatMap { b.rejects[$0.0.rawValue] } ?? "-")")
            // SL-26: 炉を焚き火の近くに置く
            b.goHome()
            if snapshots { out.snaps["SL-26"] = b }
            let fireAt = b.campfire().flatMap { b.w.placements.items[$0]?.at.point } ?? b.w.map.spawn.point
            var furnace: EntityID?
            var why = "-"
            let firedBeforeFurnace = Set(b.w.narrative.fired.keys)
            search: for r in 2...7 {
                for dy in -r...r {
                    for dx in -r...r where max(abs(dx), abs(dy)) == r {
                        let at = WorldPoint(.surface, fireAt + GridPoint(dx, dy))
                        let res = b.send(.production(.place(module: furnaceKind, at: at, facing: .north)))
                        if let j = res.rejection {
                            why = j.reason.rawValue
                            if why.hasSuffix("missing_cost") || why.hasSuffix("locked") { break search }
                        } else {
                            furnace = b.w.placements.sortedIDs.first { b.w.placements.items[$0]?.kind == .module(furnaceKind) }
                            break search
                        }
                    }
                }
            }
            out.ok["炉を置いた"] = furnace != nil
            guard let f = furnace else {
                let have = furnaceCost.compactMap { i in i.item.map { "\($0.rawValue) \(b.count($0))/\(i.quantity)" } }
                let far = furnaceCost.compactMap { i in i.item }.filter { b.count($0) == 0 }.map { b.distanceToSource($0) }
                stop("SL-26 炉(\(why) 材料 \(have) 無い物の元まで \(far))")
                break iron
            }
            mark("SL-26 炉")
            // SL-26: 置いてから 10 秒以内に、頼んでいない仲間が上書きの持ち場で歩き出す。置いた事で場面が始まる
            do {
                let t0 = b.real
                let firedBefore = firedBeforeFurnace
                var helper: Double?
                var m = 0
                while b.real - t0 <= 10 && m < 200 {
                    b.steps(1)
                    m += 1
                    if helper == nil, b.w.people.persons.values.contains(where: { $0.id != PersonID.noah && $0.override != nil && $0.motion != nil }) {
                        helper = b.real - t0
                    }
                }
                b.readScenes()
                let scene = b.w.narrative.fired.keys.contains { !firedBefore.contains($0) && Self.hasScene($0, content) }
                out.ok["炉に仲間が寄る"] = helper != nil
                out.ok["炉の場面"] = scene
                if let h = helper { out.milestones.append(("SL-26 仲間が歩き出す(+\(Int(h))s)", b.real)) }
            }
            // SL-27: 予熱して 1100℃ → 試す
            let pre = b.send(.base(.hearth(placement: f, op: .preheat)))
            if let j = pre.rejection { out.diag.append("予熱: \(j.reason.rawValue)") }
            var hot = false
            n = 0
            while !hot && n < 4000 {
                b.steps(1)
                n += 1
                if let pl = b.w.placements.items[f], let t = FurnaceHeat.temperature(pl, content),
                   let d = FurnaceHeat.def(pl, content), t >= d.work { hot = true }
            }
            out.ok["1100℃"] = hot
            guard hot else { stop("SL-27 予熱"); break iron }
            mark("SL-27 熱")
            guard let sel = b.fb.designBench(in: b.w).materials.first?.selector else { stop("SL-27 鉱石が無い"); break iron }
            let firedBeforeTrial = Set(b.w.narrative.fired.keys)
            let tr = b.send(.invention(.trial(input: sel, quantity: 1, steps: [.charcoalFurnace])))
            if let j = tr.rejection {
                let mats = b.fb.designBench(in: b.w).materials.map { "\($0.name) \($0.quantity)" }
                out.diag.append("試す: \(j.reason.rawValue) 材料 \(mats)")
            }
            b.steps(4)
            out.ok["最初の鉄"] = b.w.ledger.records.contains { $0.tags.contains(InventionTags.firstSmelt) }
            guard out.ok["最初の鉄"] == true else { stop("SL-27 試す"); break iron }
            mark("SL-27 最初の鉄")
            b.readScenes()
            out.ok["最初の鉄の場面"] = b.w.narrative.fired.keys.contains { !firedBeforeTrial.contains($0) && Self.hasScene($0, content) }
        }
        out.log = b.log
        out.answers = b.answers
        out.leaks = b.leaks
        if b.cooldownHits > 0 { out.diag.append("間を置くマスで断られた \(b.cooldownHits) 回") }
        if !b.noSource.isEmpty { out.diag.append("産む行為が無い物 \(b.noSource.sorted())") }
        if !b.gatherMiss.isEmpty { out.diag.append("採れなかった: \(b.gatherMiss.sorted { $0.key < $1.key })") }
        return out
    }

    func testFirstTenMinutesTimeline() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        // 10 分の内容(非公開の層の ten-min)が本線の層に入るまでは、環境変数で明示した時だけ回す(古い層では段に届かず落ちる)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REFORGE_TENMIN_BOT"] == "1",
                          "REFORGE_TENMIN_BOT=1 の時だけ回す(10 分の内容が入った層で)")
        setvbuf(stdout, nil, _IOLBF, 0)  // 結果の行が、途中で止まっても残るように
        var content = try TestContent.full()
        content.failureRules = [:]
        let picks = try Picks(content)
        XCTAssertFalse(picks.shelter.isEmpty, "寝床のある建造物が無い")
        let env = ProcessInfo.processInfo.environment
        let seeds = Int(env["REFORGE_TENMIN_SEEDS"] ?? "") ?? 5
        let from = UInt64(env["REFORGE_TENMIN_SEED_FROM"] ?? "") ?? 0
        let stack = env["REFORGE_TENMIN_STACK"] == "1"
        // 名乗る前の名前の監査は、毎歩 Frame を作るので最初の数 seed だけ(REFORGE_TENMIN_NAMES、既定 2)
        let namesSeeds = Int(env["REFORGE_TENMIN_NAMES"] ?? "") ?? 2
        let named = Self.namedPeople(content)
        var leaks: [String] = []
        var failed: [String: Int] = [:]
        var fireAtDawn = 0
        var shelterAt: [Int] = []
        var worstGap = 0.0
        // INV-S3: 応え(場面を始める出来事)と応えの間。600 秒までの間のうち 90 秒を超えるものを、前後の出来事の組で数える
        var longGaps: [String: [Int]] = [:]
        var gapStarts: [String: [Int]] = [:]
        var seedsOver = 0
        var overByPart: [String: Int] = [:]
        // SL-23〜27 の段の時刻と、止まった所
        var stageTimes: [String: [Int]] = [:]
        var stopped: [String] = []
        var outOfWindow: [String] = []
        var materialSecs: [Int] = []
        var stuck: [UInt64] = []
        var overList: [String] = []
        var worstAnswerGap = 0
        for seed in from..<(from + UInt64(seeds)) {
            let r = run(seed: seed, content: content, picks: picks, stack: stack,
                        nameAudit: seed < UInt64(namesSeeds) ? named : [])
            leaks += r.leaks.map { "seed \(seed) \($0)" }
            for (k, v) in r.ok where !v { failed[k, default: 0] += 1 }
            if r.fireAtDawn { fireAtDawn += 1 }
            for (name, t) in r.milestones {
                let key = String(name.split(separator: "(").first ?? Substring(name))
                stageTimes[key, default: []].append(Int(t))
                if let (lo, hi) = Self.window[key], Int(t) < lo - 30 || Int(t) > hi + 30 {
                    outOfWindow.append("seed \(seed) \(key) \(Int(t))s(目安 \(lo)〜\(hi)s)")
                }
            }
            if let at = r.stoppedAt { stopped.append("seed \(seed): \(at)") }
            if let m = r.material {
                materialSecs.append(Int(m.seconds))
                if m.stuck { stuck.append(seed) }
            }
            if let id = r.shelterScene, let t = r.log.first(where: { $0.0 == id })?.1 { shelterAt.append(Int(t)) }
            let times = r.log.map(\.1).filter { $0 <= 600 }
            worstGap = max(worstGap, zip(times, times.dropFirst()).map { $1 - $0 }.max() ?? 0)
            // 応え = 場面を始める出来事・人の一言・頼んだ後の最初の作業の字(game-designer の数え方。長押しの 1 行はボットが押さないので入らない)
            // 測る範囲は火から最初の鉄まで(鉄に届かなければ 600 秒まで)
            let end = r.milestones.first { $0.0.hasPrefix("SL-27 最初の鉄") }?.1 ?? 600
            let answers = (r.log.filter { Self.hasScene($0.0, content) }.map { ("scene:\($0.0.rawValue)", $0.1) } + r.answers)
                .filter { $0.1 <= end }
                .enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }.map(\.element)
            var over = false
            var mine: [String] = []
            for (a, b) in zip(answers, answers.dropFirst()) {
                let gap = Int(b.1 - a.1)
                worstAnswerGap = max(worstAnswerGap, gap)
                if gap > 90 {
                    let key = "\(a.0) → \(b.0)"
                    longGaps[key, default: []].append(gap)
                    gapStarts[key, default: []].append(Int(a.1))
                    over = true
                    let part: String
                    if let (m0, m1) = r.materialWindow, a.1 < m1, b.1 > m0 {
                        part = "材料集め"
                    } else if let t = r.milestones.first?.1, a.1 >= t - 30 {
                        part = "石槌から鉄"
                    } else {
                        part = "それ以外"
                    }
                    overByPart[part, default: 0] += 1
                    mine.append("\(Int(a.1))→\(Int(b.1))s [\(part)] \(a.0) → \(b.0)")
                }
            }
            if over {
                seedsOver += 1
                overList.append("seed \(seed): " + mine.joined(separator: " / "))
            }
            if seed == 0 {
                print("[SL-40] seed 0 応え: " + answers.map { "\($0.0)@\(Int($0.1))s" }.joined(separator: " "))
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
        print("[INV-S3] \(seeds) seed: 応えの間が 90 秒を超えた seed \(seedsOver) / いちばん長い間 \(worstAnswerGap) 秒"
              + " / 超えた間の数 \(overByPart.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "・"))")
        for (k, v) in longGaps.sorted(by: { $0.value.count > $1.value.count }).prefix(12) {
            let g = v.sorted()
            let st = (gapStarts[k] ?? []).sorted()
            print("[INV-S3]   \(k): \(v.count) seed(間 中央 \(g[g.count / 2]) 秒・最長 \(g.last!) 秒。始まり 中央 \(st[st.count / 2]) 秒)")
        }
        for line in overList { print("[INV-S3-seed] \(line)") }
        for (k, v) in stageTimes.sorted(by: { $0.key < $1.key }) {
            let g = v.sorted()
            let w = Self.window[k].map { "目安 \($0.0)〜\($0.1)s" } ?? ""
            print("[SL-40] \(k): \(v.count) seed 中央 \(g[g.count / 2])s・最短 \(g.first!)s・最長 \(g.last!)s \(w)")
        }
        print("[SL-40] 目安から ±30 秒の外 \(outOfWindow.count) 件 / 最初の鉄の前で止まった \(stopped.count) seed")
        for l in outOfWindow.prefix(30) { print("[SL-40-window] \(l)") }
        for l in stopped { print("[SL-40-stop] \(l)") }
        materialSecs.sort()
        if !materialSecs.isEmpty {
            print("[SL-40] シェルターの材料集め: 中央 \(materialSecs[materialSecs.count / 2]) 秒・最長 \(materialSecs.last!) 秒 / 60 回で詰まった seed \(stuck)")
        }
        print("[TEST-F9] 名乗りで名前が開く人 \(named.count)(\(named.map { "\($0.0.rawValue)←\($0.2.rawValue)" }.joined(separator: " ")))"
            + " / 監査した seed \(min(namesSeeds, seeds)) / 名乗る前に名前が出た \(leaks.count) 件")
        for l in leaks { print("[TEST-F9]   \(l)") }
        print("[SL-40] \(seeds) seed: 届かなかった段 \(failed.sorted { $0.key < $1.key })")
        XCTAssertEqual(failed, [:], "届かなかった段がある")
        XCTAssertEqual(leaks, [], "名乗る前の名前が画面に出た(TEST-F9)")
    }
}
