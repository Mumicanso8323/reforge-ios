import XCTest
@testable import ReForgeCore

/// TEST-06(成立性、RISK-02): 固定方針ボットが seed 0〜99 の 100 走すべてで勝利する。
/// 方針: 伐採 → 焚き火台 → 農場 → 採石 → 井戸 → 採掘 → 炭焼き → 板金 → 炉。余りは食料・水を 2 日分維持。
final class T06_FeasibilityBotTests: XCTestCase {
    let g = Fixture.game

    struct Bot {
        let g: Game
        /// 2 日分 + 余裕(消費の大半は夜に来るので、行動の時点で 2 日分を切らない)。
        func reserve(_ s: GameState) -> Int { s.population * 2 + 2 }

        func upkeep(_ s: GameState) -> Action? {
            if s.quantity(ID.water) < reserve(s) { return .gather(.water) }
            if s.quantity(ID.food) + s.quantity(ID.ration) < reserve(s) { return .gather(.food) }
            return nil
        }

        func need(_ s: GameState, _ item: ItemID, _ n: Int, by action: Action) -> Action? {
            s.quantity(item) < n ? action : nil
        }

        /// 次の進歩の一手(昼)。
        func progress(_ s: GameState) -> Action? {
            if !s.has(ID.campfire) {
                return need(s, ID.plantFiber, 2, by: .gather(.wood)) ?? need(s, ID.wood, 2, by: .gather(.wood))
                    ?? .build(ID.campfire)
            }
            if !s.has(ID.simpleFarm) {
                return need(s, ID.plantFiber, 3, by: .gather(.wood)) ?? need(s, ID.wood, 5, by: .gather(.wood))
                    ?? .build(ID.simpleFarm)
            }
            if !s.has(ID.well) {
                return need(s, ID.stone, 4, by: .gather(.stone)) ?? need(s, ID.wood, 4, by: .gather(.wood))
                    ?? .build(ID.well)
            }
            let ingotsNeeded = max(0, 4 - s.quantity(ID.ironIngot) - 2 * s.quantity(ID.ironPlate))
            if !s.has(ID.basicFurnace) {
                if let a = need(s, ID.ironOre, ingotsNeeded, by: .gather(.ore)) { return a }
                if s.quantity(ID.coal) + s.quantity(ID.charcoal) < ingotsNeeded { return .gather(.ore) }
            }
            if !s.has(ID.charcoalPit) {
                return need(s, ID.stone, 4, by: .gather(.stone)) ?? need(s, ID.wood, 6, by: .gather(.wood))
                    ?? .build(ID.charcoalPit)
            }
            if !s.has(ID.basicFurnace) {
                if let craft = smithing(s) { return craft }
                return need(s, ID.stone, 3, by: .gather(.stone)) ?? .build(ID.basicFurnace)
            }
            return nil
        }

        /// 板金まで(昼でも夜でもできる製作)。
        func smithing(_ s: GameState) -> Action? {
            guard !s.has(ID.basicFurnace) else { return nil }
            if s.quantity(ID.ironPlate) < 2 {
                if s.quantity(ID.ironIngot) >= 2 { return .craft(ID.ironPlatePound, times: 1) }
                if Crafting.maxTimes(g.content.recipe(ID.smeltIron)!, in: s) > 0 { return .craft(ID.smeltIron, times: 1) }
            }
            return nil
        }

        func playDay(_ s: GameState) -> GameState {
            var s = s
            while s.isActive, s.phase == .day, s.actionPointsLeft > 0 {
                let a = upkeep(s) ?? progress(s) ?? .gather(s.quantity(ID.water) <= s.quantity(ID.food) ? .water : .food)
                switch g.perform(a, on: s) {
                case .success(let n): s = n
                case .failure(let e): XCTFail("ボットの手 \(a) が拒否された: \(e)"); return s
                }
            }
            if s.phase == .day { s = try! g.perform(.rest, on: s).get() }
            if g.canStartNightWork(s), smithing(s) != nil {
                s = try! g.startNightWork(s).get()
                while s.actionPointsLeft > 0, let a = smithing(s) {
                    guard case .success(let n) = g.perform(a, on: s) else { break }
                    s = n
                }
            }
            return try! g.sleep(s).get()
        }
    }

    func testBotWinsAllHundredSeeds() {
        let bot = Bot(g: g)
        var winDays: [Int] = []
        var completed: [Int] = []
        for seed in UInt64(0)..<100 {
            var s = g.newGame(seed: seed)
            var allBuiltOn: Int?
            while s.outcome == .ongoing, s.day < 40 {
                s = bot.playDay(s)
                if allBuiltOn == nil, Balance.mvp.victoryBuildings.allSatisfy(s.has) { allBuiltOn = s.day }
            }
            XCTAssertEqual(s.outcome, .victory, "seed \(seed): \(s.outcome) \(s.day) 日目")
            winDays.append(s.day)
            completed.append(allBuiltOn ?? 99)
        }
        XCTAssertEqual(Set(winDays), [30])
        // 3 つの建造物がそろう日(§6.6 の机上計算では 9〜10 日。参考値として上限だけ見る)
        XCTAssertLessThanOrEqual(completed.max()!, 29)
        print("TEST-06: 3 建造物がそろった日 min \(completed.min()!) / max \(completed.max()!) / 平均 \(Double(completed.reduce(0, +)) / 100)")
    }
}
