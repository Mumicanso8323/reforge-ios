import Dispatch
import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// TEST-R1-02 自動化ボット(order.md §5.8)。CORE-04・05、IN-C1〜C4。
///
/// 手作業だけのボット(ノアが掘る・運ぶ・炉で溶かす・叩く。仲間は運ぶ物が無い)と、ラインを最短で置くボット
/// (最初は手で鉄を作り、採掘口の材料がそろったらすぐ札を置く。仲間は運搬に付ける)を同じ seed で 100 走らせる。
/// - 3 日目の 1 日あたりの鉄板の生産量で、ラインが手作業の最良日の 3 倍以上
/// - 4 日目の夜明けまでに、手元の鉄板の累計で逆転
/// - 掘った鉱石のうち手で掘った割合が 1 日目 80% 以上 → 4 日目 30% 以下
///
/// 歩くのは RFCrew の担当なので、ここでは 1 秒 4 マスの時間を進めてからノアを移す(歩いた時間は同じ)。
/// 仲間の運搬の配属と activity(.carrying)も RFCrew の代わりにボットが付ける(専任の運び手は夜も運ぶ)。
///
/// 走らせるシステムは、時間・生産・運搬・発明(ライン札)だけに絞る(Bot.systems)。人の歩く・見る・出来事の計算は
/// この受け入れ条件(ラインと手作業の量の比べ)に関わらず、debug ビルドで 100 走が重くなるため。
final class ProductionBotTests: XCTestCase {
    /// 試験用の重ね(R1 の値: 1 回の処理 = ゲーム 9600 秒、手作業 塊 8 / 板 16 回、採掘 12 回で鉱脈 1 回)。
    /// 採掘口は鉄板 6 枚と薪、叩き台は最初の鉄の塊 1 つと薪で作る。仲間 4 人(R1 の初期の人数)。
    static let overlay = """
    {
      "mapGen": { "size": { "width": 64, "height": 64 }, "parameters": null },
      "people": [ { "id": "person.test_d", "name": "person:person.test_d", "specialties": ["mining"], "ideology": {} } ],
      "start": {
        "members": ["person.noah", "person.test_a", "person.test_b", "person.test_c", "person.test_d"],
        "items": [ { "item": "wood", "min": 20, "max": 20 }, { "item": "charcoal", "min": 200, "max": 200 } ],
        "facts": [],
        "unlocks": [
          { "module": { "id": "minehead" } }, { "module": { "id": "furnace" } }, { "module": { "id": "anvil" } },
          { "handwork": { "id": "handwork.mine" } }, { "handwork": { "id": "handwork.smelt" } },
          { "handwork": { "id": "handwork.hammer" } }
        ]
      },
      "modules": [
        { "id": "minehead", "placement": { "requiresDeposit": true },
          "cost": [ { "item": "wood", "quantity": 2 },
                    { "matter": { "substance": "Fe", "stage": "metal", "shapes": ["plate"] }, "quantity": 6 } ],
          "ports": [ { "side": "north", "flow": "output" } ], "cycleSeconds": 9600, "specialty": "mining" },
        { "id": "furnace", "placement": {}, "cost": [ { "item": "wood", "quantity": 2 } ],
          "ports": [ { "side": "south", "flow": "input" }, { "side": "north", "flow": "output" } ],
          "cycleSeconds": 9600, "batch": 2, "specialty": "smith" },
        { "id": "anvil", "placement": {},
          "cost": [ { "item": "wood", "quantity": 1 },
                    { "matter": { "substance": "Fe", "stage": "metal", "shapes": ["lump"] }, "quantity": 1 } ],
          "ports": [ { "side": "south", "flow": "input" }, { "side": "north", "flow": "output" } ],
          "cycleSeconds": 9600, "batch": 2, "specialty": "smith" }
      ],
      "handwork": [ { "id": "handwork.mine", "presses": 12, "onDeposit": true, "promotedBy": ["minehead"] } ]
    }
    """

    static func content() throws -> ContentDB {
        var c = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(overlay.utf8), to: &c, name: "production-bot")
        return c
    }

    struct DayLog: Equatable {
        var plates: [Int: Int] = [:]
        var handOre: [Int: Int] = [:]
        var lineOre: [Int: Int] = [:]
        var platesOnHandAtDawn: [Int: Int] = [:]
    }

    /// ボットの共通の道具。
    struct Bot {
        let sim: Simulation
        var w: WorldState
        let deposit: GridPoint
        let home: GridPoint
        var log = DayLog()

        static let walkTilesPerSecond = 4.0
        static let pressRealSeconds = 1.0

        /// 量の比べに要るシステムだけ(本体の並びの順を保つ)。
        static var systems: [any SimSystem] { [TimeSystem(), ProductionSystem(), LogisticsSystem(), InventionSystem()] }

        init(rig: TestRig, seed: UInt64, systems: [any SimSystem] = Bot.systems) {
            sim = Simulation(content: rig.content, systems: systems)
            w = rig.factory.newWorld(seed: seed)
            home = w.map.spawn.point
            // 鉄の露頭(純度 20〜35%、30〜70 回)を、拠点の西 8〜20 マスに置く(seed で変わる)
            var rng = SeededRandom(state: seed &* 0x9E37_79B9_7F4A_7C15 &+ 1)
            let area = w.base.area!
            let d = rng.int(in: 8...20)
            deposit = GridPoint(area.origin.x - d, home.y + rng.int(in: -6...6))
            let dep = DepositGenerator.make(id: "deposit.outcrop", at: deposit, category: .iron, rng: &rng,
                                            primaryPercent: 20...35)
            w.map[.surface]?.deposits.add(dep)
        }

        var day: Int { w.clock.day }
        var isDay: Bool { w.clock.phase == .day && w.run.isActive }

        mutating func tick(_ s: Double = 1.0) {
            var left = s
            while left > 0 && isDay {
                _ = sim.advance(&w, realSeconds: min(1.0, left))
                left -= 1.0
            }
        }

        mutating func walk(to p: GridPoint) {
            guard let from = w.people[.noah]?.position?.point, from != p else { return }
            tick(Double(from.chebyshev(to: p)) / Self.walkTilesPerSecond)
            w.people[.noah]?.position = WorldPoint(.surface, p)
        }

        func pocket(_ f: (Matter) -> Bool) -> (Int, Stuff?) {
            var n = 0
            var stuff: Stuff?
            for e in w.inventory.entries(.person(.noah)) {
                if case .matter(let m) = e.stuff, f(m) {
                    n += e.quantity
                    stuff = stuff ?? e.stuff
                }
            }
            return (n, stuff)
        }

        static func isOre(_ m: Matter) -> Bool { m.stage == .ore }
        static func isLump(_ m: Matter) -> Bool { m.stage == .metal && m.shape == .lump }
        static func isPlate(_ m: Matter) -> Bool { m.stage == .metal && m.shape == .plate }

        /// 押し続ける。until が成り立つか、続けられなくなるか、日が暮れるまで。
        mutating func hold(_ id: HandworkID, _ stuff: Stuff?, until done: (WorldState) -> Bool = { _ in false }) {
            let sel = stuff.map { StockSelector(holder: .person(.noah), stuff: $0) }
            guard sim.apply(.production(.handwork(id: id, input: sel, holding: true)), to: &w).rejection == nil else { return }
            while isDay && w.placements.handwork[.noah]?.holding == true && !done(w) { tick() }
            _ = sim.apply(.production(.handwork(id: id, input: sel, holding: false)), to: &w)
        }

        /// 昼の残りの実秒。
        var dayLeft: Double {
            let def = sim.content.clock
            let used = (w.clock.now - w.clock.dayStartedAt).seconds
            return Double(def.dayGameSeconds - used) * Double(def.dayRealSeconds) / Double(def.dayGameSeconds)
        }

        /// 手元の鉱石を溶かし、塊を叩く(keepLumps 個は叩かずに残す)。
        mutating func craft(keepLumps: Int = 0, maxPlates: Int = .max) {
            let (_, ore) = pocket(Self.isOre)
            if let ore { hold("handwork.smelt", ore) }
            var made = 0
            while isDay, made < maxPlates {
                let (lumps, lump) = pocket(Self.isLump)
                guard lumps > keepLumps, let lump else { break }
                let before = pocket(Self.isPlate).0
                let target = min(maxPlates - made, lumps - keepLumps)
                hold("handwork.hammer", lump) { w in
                    var n = 0
                    for e in w.inventory.entries(.person(.noah)) {
                        if case .matter(let m) = e.stuff, Bot.isPlate(m) { n += e.quantity }
                    }
                    return n - before >= target
                }
                let after = pocket(Self.isPlate).0
                if after == before { break }
                made += after - before
            }
        }

        /// 鉱脈まで歩いて n 個になるまで掘り、拠点へ戻る。
        mutating func mine(until n: Int) {
            guard pocket(Self.isOre).0 < n else { return }
            walk(to: GridPoint(deposit.x + 1, deposit.y))
            hold("handwork.mine", nil) { w in
                var k = 0
                for e in w.inventory.entries(.person(.noah)) {
                    if case .matter(let m) = e.stuff, m.stage == .ore { k += e.quantity }
                }
                return k >= n
            }
            walk(to: home)
        }

        /// 夜を寝て、夜明けに 1 日を記録する。
        mutating func sleepAndLog() {
            while w.clock.phase == .day && w.run.isActive { tick() }
            let d = day
            _ = sim.apply(.time(.sleep), to: &w)
            record(day: d)
        }

        mutating func record(day d: Int) {
            for r in w.ledger.records where r.day == d {
                switch (r.act, r.subject) {
                case (.crafted, _) where r.detail["module"] == .string("anvil"): log.plates[d, default: 0] += r.count
                case (.produced, .module(let k, _)) where k == .anvil: log.plates[d, default: 0] += r.count
                case (.mined, _): log.handOre[d, default: 0] += r.count
                case (.produced, .module(let k, _)) where k == .minehead: log.lineOre[d, default: 0] += r.count
                default: break
                }
            }
            var onHand = 0
            for h in [HolderID.base, .person(.noah)] {
                for e in w.inventory.entries(h) {
                    if case .matter(let m) = e.stuff, Self.isPlate(m) { onHand += e.quantity }
                }
            }
            log.platesOnHandAtDawn[w.clock.day] = onHand
        }
    }

    /// 手作業だけ: 毎日、昼の残りで作れるだけの鉱石を掘って、溶かして叩く。
    static func handOnly(rig: TestRig, seed: UInt64, days: Int) -> DayLog {
        var b = Bot(rig: rig, seed: seed)
        while b.day <= days && b.w.run.isActive {
            b.craft()
            let walk = 2 * Double(b.home.chebyshev(to: b.deposit)) / Bot.walkTilesPerSecond
            // 1 個 = 掘る 6 + 溶かす 8 + 叩く 16 回
            let n = Int((b.dayLeft - walk - 2) / (30 * Bot.pressRealSeconds))
            if n >= 2 {
                b.mine(until: n - n % 2)
                b.craft()
            }
            b.sleepAndLog()
        }
        return b.log
    }

    /// ラインを最短で置く: 叩き台の塊 1 つと採掘口の鉄板 6 枚を手で作り、そろったらすぐに置く。
    static func line(rig: TestRig, seed: UInt64, days: Int, systems: [any SimSystem] = Bot.systems) -> DayLog {
        var b = Bot(rig: rig, seed: seed, systems: systems)
        var placed = false
        let furnaceAt = WorldPoint(.surface, b.home)
        let anvilAt = WorldPoint(.surface, GridPoint(b.home.x + 1, b.home.y))
        while b.day <= days && b.w.run.isActive {
            while !placed && b.isDay {
                let plates = b.pocket(Bot.isPlate).0
                let lumps = b.pocket(Bot.isLump).0
                if plates >= 6 && lumps >= 1 {
                    let des = b.sim.apply(.invention(.makeDesign(steps: [.minehead, .charcoalFurnace, .anvil])), to: &b.w)
                    precondition(des.rejection == nil)
                    let d = b.w.invention.designs.keys.max()!
                    _ = b.sim.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: furnaceAt, facing: .east)), to: &b.w)
                    _ = b.sim.apply(.production(.placeFromDesign(design: d, stepIndex: 2, at: anvilAt, facing: .east)), to: &b.w)
                    b.walk(to: GridPoint(b.deposit.x + 1, b.deposit.y))
                    let r = b.sim.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: WorldPoint(.surface, b.deposit),
                                                                     facing: .east)), to: &b.w)
                    precondition(r.rejection == nil, "\(r.rejection!.reason)")
                    _ = b.sim.runSteps(1, &b.w)
                    // 仲間を全員、採掘口 → 炉の運搬に専任で付ける(夜も運ぶ)
                    let mine = b.w.placements.at(WorldPoint(.surface, b.deposit))[0]
                    let route = b.w.logistics.routes.values.first { $0.from == .placement(mine) }!.id
                    for p in b.w.people.members where p != .noah {
                        b.w.people[p]?.assignment = .haul(route: route)
                        b.w.people[p]?.activity = .carrying(route: route)
                    }
                    b.walk(to: b.home)
                    placed = true
                    break
                }
                // 足りない分を手で作る(塊 1 つは残す)
                let needOre = max(0, 6 - plates + 1 - lumps) - b.pocket(Bot.isOre).0
                if needOre > 0 { b.mine(until: b.pocket(Bot.isOre).0 + needOre + needOre % 2) }
                b.craft(keepLumps: 1, maxPlates: 6 - plates)
                if b.pocket(Bot.isPlate).0 == plates && b.pocket(Bot.isLump).0 == lumps && b.pocket(Bot.isOre).0 == 0 {
                    b.tick()
                }
            }
            b.sleepAndLog()
        }
        return b.log
    }

    func testR1_02_LineBeatsHandwork() throws {
        _ = try Self.content()
        // 既定 100 走(手元と夜間)。CI は REFORGE_R1_02_SEEDS=20(.github/workflows/ci.yml)
        let n = Int(ProcessInfo.processInfo.environment["REFORGE_R1_02_SEEDS"] ?? "") ?? 100
        let seeds = Array(UInt64(0)..<UInt64(n))
        final class Box: @unchecked Sendable {
            var results: [(DayLog, DayLog)?]
            let lock = NSLock()
            init(_ n: Int) { results = Array(repeating: nil, count: n) }
        }
        let box = Box(seeds.count)
        // 走りごとにコンテンツを読み直す(共有すると参照カウントの取り合いで並列が効かない)
        DispatchQueue.concurrentPerform(iterations: seeds.count) { i in
            let rig = TestRig(content: try! Self.content())
            let hand = Self.handOnly(rig: rig, seed: seeds[i], days: 4)
            let line = Self.line(rig: rig, seed: seeds[i], days: 4)
            box.lock.lock()
            box.results[i] = (hand, line)
            box.lock.unlock()
        }
        let results = box.results
        var worstRatio = Double.infinity
        for (i, r) in results.enumerated() {
            let (hand, line) = try XCTUnwrap(r)
            let best = (1...4).map { hand.plates[$0, default: 0] }.max() ?? 0
            let line3 = line.plates[3, default: 0]
            worstRatio = min(worstRatio, Double(line3) / Double(max(1, best)))
            XCTAssertGreaterThanOrEqual(line3, 3 * best, "seed \(i): 3 日目のライン \(line3) / 手作業の最良日 \(best)")
            XCTAssertGreaterThanOrEqual(line.platesOnHandAtDawn[4, default: 0], hand.platesOnHandAtDawn[4, default: 0],
                                        "seed \(i): 4 日目の夜明けまでに累計で逆転")
            func handShare(_ d: Int) -> Int {
                let h = line.handOre[d, default: 0], l = line.lineOre[d, default: 0]
                return h + l == 0 ? 0 : h * 100 / (h + l)
            }
            XCTAssertGreaterThanOrEqual(handShare(1), 80, "seed \(i): 1 日目は手作業が 8 割以上")
            XCTAssertLessThanOrEqual(handShare(4), 30, "seed \(i): 4 日目は手作業が 3 割以下")
            if i == 0 {
                print("TEST-R1-02 seed 0 手作業", (1...4).map { hand.plates[$0, default: 0] },
                      "ライン", (1...4).map { line.plates[$0, default: 0] },
                      "手で掘った/ラインが掘った", (1...4).map { (line.handOre[$0, default: 0], line.lineOre[$0, default: 0]) })
            }
        }
        print("TEST-R1-02 3 日目のライン / 手作業の最良日 の最小", worstRatio)
    }
}
