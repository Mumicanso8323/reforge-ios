import XCTest
@testable import ReForgeCore

/// TEST-02: 各行動の増減が §6.3〜§6.5 の表と一致する(確率項目は seed 固定で期待値列を固定)。
final class T02_ActionTests: XCTestCase {
    let g = Fixture.game

    private func delta(_ a: Action, from s: GameState) -> [ItemID: Int] {
        let n = g.must(a, s)
        var d: [ItemID: Int] = [:]
        for id in Set(s.inventory.keys).union(n.inventory.keys) {
            let x = n.quantity(id) - s.quantity(id)
            if x != 0 { d[id] = x }
        }
        XCTAssertEqual(n.actionPointsLeft, s.actionPointsLeft - 1, "\(a) は 1 行動")
        return d
    }

    func testDeterministicGathers() {
        let s = g.newGame(seed: 1)
        XCTAssertEqual(delta(.gather(.food), from: s), [ID.food: 4])
        XCTAssertEqual(delta(.gather(.food), from: s.withBuildings([ID.campfire])), [ID.food: 5])
        XCTAssertEqual(delta(.gather(.water), from: s), [ID.water: 4])
        XCTAssertEqual(delta(.gather(.ore), from: s), [ID.ironOre: 3, ID.coal: 2])
    }

    func testChopWoodGivesFiberWithFixedSeed() {
        var s = g.newGame(seed: 42)
        var fiberHits: [Bool] = []
        for _ in 0..<10 {
            let before = s
            s = g.must(.gather(.wood), before)
            XCTAssertEqual(s.quantity(ID.wood) - before.quantity(ID.wood), 5)
            let fiber = s.quantity(ID.plantFiber) - before.quantity(ID.plantFiber)
            XCTAssertTrue(fiber == 0 || fiber == 1)
            fiberHits.append(fiber == 1)
        }
        XCTAssertEqual(fiberHits, T02_ActionTests.expectedFiberSeed42)
    }

    func testQuarryGivesClayWithFixedSeed() {
        var s = g.newGame(seed: 42)
        var clayHits: [Bool] = []
        for _ in 0..<10 {
            let before = s
            s = g.must(.gather(.stone), before)
            XCTAssertEqual(s.quantity(ID.stone) - before.quantity(ID.stone), 3)
            clayHits.append(s.quantity(ID.clay) > before.quantity(ID.clay))
        }
        XCTAssertEqual(clayHits, T02_ActionTests.expectedClaySeed42)
    }

    func testProbabilitiesConvergeToTable() {
        // 1 万回で 20% / 30% に近いこと(乱数の偏りの確認)
        var rng = SeededRandom(state: 7)
        let fiber = (0..<10_000).filter { _ in rng.chance(percent: 20) }.count
        XCTAssertEqual(Double(fiber) / 10_000, 0.20, accuracy: 0.015)
        let clay = (0..<10_000).filter { _ in rng.chance(percent: 30) }.count
        XCTAssertEqual(Double(clay) / 10_000, 0.30, accuracy: 0.015)
    }

    func testScavengeTenTimesThenExhausted() {
        var s = g.newGame(seed: 42)
        s.actionPointsLeft = 99
        var rations: [Int] = []
        for i in 0..<10 {
            let before = s
            s = g.must(.gather(.scavenge), before)
            let got = s.quantity(ID.ration) - before.quantity(ID.ration)
            XCTAssertTrue((2...4).contains(got))
            XCTAssertEqual(s.scavengeRemaining, 9 - i)
            rations.append(got)
        }
        XCTAssertEqual(rations, T02_ActionTests.expectedScavengeSeed42)
        XCTAssertEqual(g.perform(.gather(.scavenge), on: s), .failure(.scavengeExhausted))
        XCTAssertEqual(Fixture.text.journal(s.log.last!), "残骸の区画を漁った。保存食 +\(rations.last!)(あと 0 回)")
    }

    func testCrafting() {
        var s = g.newGame(seed: 1).withBuildings([ID.campfire])
        s = s.with(ID.ironOre, 2).with(ID.coal, 1).with(ID.charcoal, 0).with(ID.plantFiber, 1)

        XCTAssertEqual(delta(.craft(ID.charcoalBurn, times: 1), from: s), [ID.wood: -3, ID.charcoal: 2])
        XCTAssertEqual(delta(.craft(ID.smeltIron, times: 1), from: s), [ID.ironOre: -1, ID.coal: -1, ID.ironIngot: 1])
        // 石炭が無ければ木炭で製錬する
        XCTAssertEqual(delta(.craft(ID.smeltIron, times: 1), from: s.with(ID.coal, 0).with(ID.charcoal, 1)),
                       [ID.ironOre: -1, ID.charcoal: -1, ID.ironIngot: 1])
        XCTAssertEqual(delta(.craft(ID.ironPlatePound, times: 1), from: s.with(ID.ironIngot, 2)),
                       [ID.ironIngot: -2, ID.ironPlate: 1])
        XCTAssertEqual(delta(.craft(ID.rationRecipe, times: 1), from: s), [ID.food: -3, ID.plantFiber: -1, ID.ration: 2])

        // 複数回: 1 回 1 行動
        let twice = g.must(.craft(ID.charcoalBurn, times: 2), s)
        XCTAssertEqual(twice.actionPointsLeft, s.actionPointsLeft - 2)
        XCTAssertEqual(twice.quantity(ID.charcoal), 4)
        XCTAssertEqual(Fixture.text.journal(twice.log.last!), "木炭を焼いた(2 回)。木炭 +4")
    }

    func testCraftingRequirements() {
        let s = g.newGame(seed: 1)
        XCTAssertEqual(g.perform(.craft(ID.charcoalBurn, times: 1), on: s),
                       .failure(.needsBuilding([ID.campfire, ID.charcoalPit])))
        XCTAssertEqual(g.perform(.craft(ID.ironPlatePound, times: 1), on: s), .failure(.needsBuilding([ID.campfire])))
        let fire = s.withBuildings([ID.campfire])
        XCTAssertEqual(g.perform(.craft(ID.ironPlatePound, times: 1), on: fire),
                       .failure(.insufficient([ID.ironIngot], have: 0, need: 2)))
        XCTAssertEqual(g.perform(.craft(ID.smeltIron, times: 1), on: fire),
                       .failure(.insufficient([ID.coal, ID.charcoal], have: 0, need: 1)))
        XCTAssertEqual(Fixture.text.message(for: .insufficient([ID.ironOre], have: 0, need: 1)), "鉄鉱石が足りません(0/1)")
        // 炭焼き窯だけでも木炭は焼ける
        XCTAssertNoThrow(try g.perform(.craft(ID.charcoalBurn, times: 1), on: s.withBuildings([ID.charcoalPit])).get())
        // 行動ポイントを超える回数は作れない
        var tired = fire
        tired.actionPointsLeft = 1
        XCTAssertEqual(g.perform(.craft(ID.charcoalBurn, times: 2), on: tired), .failure(.noActionPoints))
        XCTAssertEqual(Crafting.maxTimes(g.content.recipe(ID.charcoalBurn)!, in: fire), 6, "木材 20 / 3")
    }

    func testBuilding() {
        var s = g.newGame(seed: 1).with(ID.plantFiber, 2)
        XCTAssertEqual(delta(.build(ID.campfire), from: s), [ID.wood: -2, ID.plantFiber: -2])
        s = g.must(.build(ID.campfire), s)
        XCTAssertTrue(s.hasFire)
        XCTAssertEqual(s.buildings, [Building(id: ID.campfire, builtOnDay: 1)])
        XCTAssertEqual(Fixture.text.journal(s.log.last!), "焚き火台を建てた")
        XCTAssertEqual(g.perform(.build(ID.campfire), on: s.with(ID.plantFiber, 9)), .failure(.alreadyBuilt(ID.campfire)))
        XCTAssertEqual(g.perform(.build(ID.simpleFarm), on: s),
                       .failure(.insufficient([ID.plantFiber], have: 0, need: 3)))
    }

    func testStorageCrateRaisesCap() {
        var s = g.newGame(seed: 1).with(ID.food, 58)
        s = g.must(.gather(.food), s)
        XCTAssertEqual(s.quantity(ID.food), 60, "上限 60 で止まる")
        s = s.with(ID.ironPlate, 2)
        s = g.must(.build(ID.storageCrate), s)
        XCTAssertEqual(s.cap(for: ID.food, balance: .mvp), 120)
        s = g.must(.gather(.food), s)
        XCTAssertEqual(s.quantity(ID.food), 64)
    }

    func testRestDiscardsRemainingActionsAndGoesToDusk() {
        let s = g.must(.rest, g.newGame(seed: 1))
        XCTAssertEqual(s.phase, .dusk)
        XCTAssertEqual(s.actionPointsLeft, 0)
        XCTAssertEqual(Fixture.text.journal(s.log.last!), "今日は体を休めた")
    }

    func testNoActionPointsLeft() {
        var s = g.newGame(seed: 1)
        s.actionPointsLeft = 0
        XCTAssertEqual(g.perform(.gather(.water), on: s), .failure(.noActionPoints))
        XCTAssertEqual(Fixture.text.message(for: .noActionPoints), "今日はもう動けません。休みましょう")
    }

    func testJournalWordingMatchesSpec() {
        let t = Fixture.text
        let s = g.newGame(seed: 1)
        XCTAssertEqual(t.journal(g.must(.gather(.food), s).log.last!), "食べられそうなものを集めた。食料 +4")
        XCTAssertEqual(t.journal(g.must(.gather(.water), s).log.last!), "川から水を汲んだ。水 +4")
        XCTAssertEqual(t.journal(g.must(.gather(.ore), s).log.last!), "浅い鉱脈を掘った。鉄鉱石 +3、石炭 +2")
        XCTAssertEqual(t.journal(LogEntry(day: 1, event: .gathered(.wood, gains: [ItemAmount(ID.wood, 5)], scavengeLeft: nil))),
                       "木を切り出した。木材 +5")
        XCTAssertEqual(t.journal(LogEntry(day: 1, event: .gathered(.wood, gains: [ItemAmount(ID.wood, 5), ItemAmount(ID.plantFiber, 1)], scavengeLeft: nil))),
                       "木を切り出した。木材 +5。植物繊維も手に入った +1")
        XCTAssertEqual(t.journal(LogEntry(day: 1, event: .gathered(.stone, gains: [ItemAmount(ID.stone, 3)], scavengeLeft: nil))),
                       "石を集めた。石材 +3")
        XCTAssertEqual(t.journal(LogEntry(day: 1, event: .gathered(.scavenge, gains: [ItemAmount(ID.ration, 3)], scavengeLeft: 7))),
                       "残骸の区画を漁った。保存食 +3(あと 7 回)")
        XCTAssertEqual(t.journal(LogEntry(day: 1, event: .crafted(ID.charcoalBurn, times: 1, output: ItemAmount(ID.charcoal, 2)))),
                       "木炭を焼いた。木炭 +2")
        XCTAssertEqual(t.journal(LogEntry(day: 1, event: .built(ID.well))), "井戸を建てた")
        XCTAssertEqual(t.gatherPreview(.scavenge, in: s), "保存食 +2〜4 (あと 10 回)")
        XCTAssertEqual(t.gatherPreview(.ore, in: s), "鉄鉱石 +3 石炭 +2")
        XCTAssertEqual(t.recipeFormula(g.content.recipe(ID.smeltIron)!), "鉄鉱石 1 + 石炭 1(または木炭 1) → 鉄インゴット 1")
    }

    // seed 42 で固定した期待値列(実装を変えて列が変わったら、決定性が壊れていないか確かめてから更新する)
    static let expectedFiberSeed42: [Bool] = [true, false, false, false, false, false, false, true, true, false]
    static let expectedClaySeed42: [Bool] = [true, false, false, false, false, false, true, true, true, false]
    static let expectedScavengeSeed42: [Int] = [3, 3, 2, 2, 3, 2, 3, 4, 3, 4]
}
