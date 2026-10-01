import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 生産のテストの一式(公開の試験用コンテンツ + 平らな 32×32 の草地。拠点は (11,13) から 11×7)。
struct ProductionFixture {
    let rig: TestRig
    var content: ContentDB { rig.content }
    var sim: Simulation { rig.simulation }

    static let modules: [ModuleKindID] = [.minehead, .millstone, .sluice, .mixingBowl, .furnace, .anvil, .quenchTank,
                                          "test.gathering_post", "test.boiler"]
    static let handwork: [HandworkID] = ["handwork.mine", "handwork.crush", "handwork.smelt", "handwork.hammer",
                                         "handwork.test.forage"]
    /// 拠点の中のマス。
    static let base = GridPoint(16, 16)

    init(_ edit: (inout ContentDB) -> Void = { _ in }) throws {
        var c = try TestContent.publicOnly()
        edit(&c)
        rig = TestRig(content: c)
    }

    /// 新しい世界: 全部解禁・薪と木炭を蓄えに・ノアは拠点の真ん中。
    func world(seed: UInt64 = 1, wood: Int = 40, charcoal: Int = 40) -> WorldState {
        var ctx = StepContext(world: rig.factory.newWorld(seed: seed), content: content)
        ctx.world.inventory.holders[.base] = []
        for m in Self.modules { ctx.world.research.unlocked.modules.insert(m) }
        for h in Self.handwork { ctx.world.research.unlocked.handwork.insert(h) }
        ctx.addStock(.item(.wood), wood, to: .base)
        ctx.addStock(.item(.charcoal), charcoal, to: .base)
        _ = ctx.drainEvents()
        return ctx.world
    }

    /// 鉄の鉱脈を置く(純度 percent%・回数 extractions)。
    @discardableResult
    static func addDeposit(_ w: inout WorldState, at p: GridPoint, percent: Int = 30, extractions: Int = 60,
                           id: String = "deposit.test") -> DepositID {
        let d = Deposit(id: DepositID(id), position: p, category: .iron, appearanceVariant: 0,
                        composition: [DepositComponent(.fe2o3, Purity(percent: percent)), DepositComponent(.sio2, Purity(percent: 30))],
                        extractions: extractions)
        w.map[.surface]?.deposits.add(d)
        return d.id
    }

    static func setWater(_ w: inout WorldState, at p: GridPoint) {
        w.map[.surface]?.setTerrain("water", at: p)
    }

    static func wp(_ x: Int, _ y: Int) -> WorldPoint { WorldPoint(.surface, GridPoint(x, y)) }

    func apply(_ c: Command, _ w: inout WorldState) -> StepReport { sim.apply(c, to: &w) }

    func place(_ k: ModuleKindID, _ x: Int, _ y: Int, facing: Direction = .east, _ w: inout WorldState,
               file: StaticString = #filePath, line: UInt = #line) -> EntityID {
        let r = apply(.production(.place(module: k, at: Self.wp(x, y), facing: facing)), &w)
        XCTAssertNil(r.rejection, "置けるはず: \(k) \(r.rejection?.reason.rawValue ?? "")", file: file, line: line)
        return w.placements.at(Self.wp(x, y)).first ?? EntityID(-1)
    }

    /// ライン札を作る(発明の担当のコマンドで)。
    func design(_ steps: [ProcessStep], _ w: inout WorldState, file: StaticString = #filePath, line: UInt = #line)
        -> EntityID
    {
        let before = Set(w.invention.designs.keys)
        let r = apply(.invention(.makeDesign(steps: steps)), &w)
        XCTAssertNil(r.rejection, "札にできるはず: \(r.rejection?.reason.rawValue ?? "")", file: file, line: line)
        return Set(w.invention.designs.keys).subtracting(before).first ?? EntityID(-1)
    }

    /// ゲーム時間を秒で進める(昼でも夜でも同じ step)。
    func run(seconds: Int64, _ w: inout WorldState) -> StepReport {
        sim.runSteps(Int((seconds + SimStep.gameSeconds - 1) / SimStep.gameSeconds), &w)
    }

    static var cycle: Int64 { 9600 }

    static func matterCount(_ w: WorldState, _ h: HolderID = .base, where f: (Matter) -> Bool) -> Int {
        w.inventory.entries(h).reduce(0) { acc, e in
            if case .matter(let m) = e.stuff, f(m) { return acc + e.quantity }
            return acc
        }
    }

    static func isPlate(_ m: Matter) -> Bool { m.stage == .metal && m.substance == .iron && m.shape == .plate }
}
