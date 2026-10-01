import RFContent
import RFExploration
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 探索のテストの道具: 平らな地図に自分たちの残骸を置いた世界。
struct ExploreRig {
    var content: ContentDB
    var sim: Simulation
    var world: WorldState
    let wreck: EntityID
    let wreckAt: GridPoint

    init(seed: UInt64 = 1, edit: (inout ContentDB) -> Void = { _ in }) throws {
        var c = try TestContent.publicOnly()
        edit(&c)
        content = c
        sim = Simulation(content: c)
        var w = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: seed)
        let center = w.map.spawn.point
        wreckAt = center - GridPoint(1, 1)
        let e = w.newEntityID()
        wreck = e
        var layer = w.map[.surface]!
        layer.placements.place(MapPlacement(id: .homeWreck, kind: .wreck, templateID: "wreck.home", anchor: wreckAt,
                                            footprint: .rect(width: 3, height: 2), isDiscovered: true,
                                            remainingUses: 10, entity: e))
        w.map[.surface] = layer
        world = w
    }

    var noahPos: WorldPoint { world.people[.noah]!.position! }

    mutating func put(_ p: PersonID, _ g: GridPoint) {
        world.people[p]?.position = WorldPoint(.surface, g)
        world.people[p]?.motion = nil
    }

    @discardableResult
    mutating func apply(_ c: Command) -> StepReport { sim.apply(c, to: &world) }

    @discardableResult
    mutating func steps(_ n: Int) -> StepReport { sim.runSteps(n, &world) }

    /// 行為を始めて、終わるまでステップを進める。断られたら理由を返す。
    @discardableResult
    mutating func interact(_ id: InteractionID, at g: GridPoint, holding: Bool = true) -> Rejection? {
        let r = apply(.exploration(.interact(interaction: id, at: WorldPoint(.surface, g), holding: holding)))
        if let rej = r.rejection { return rej }
        var guardN = 0
        while world.exploration.active[.noah] != nil && guardN < 1000 {
            steps(1)
            guardN += 1
        }
        return nil
    }

    func qty(_ item: ItemID) -> Int { world.inventory.quantity(item) }

    func records(_ act: ActKind) -> [ProvenanceRecord] { world.ledger.records.filter { $0.act == act } }
}
