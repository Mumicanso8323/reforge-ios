import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFTestSupport
import RFWorld
import XCTest

final class RulesTests: XCTestCase {
    /// 在庫: 合わせる・取り出すと、来歴が数つきで付いて回る(「あのとき作った鉄」を指せる)。
    func testStockCarriesProvenance() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let made = ctx.record(.crafted, .item("wood"), actor: .noah)
        ctx.addStock(.item("wood"), 4, to: .base, origin: made)
        let took = try XCTUnwrap(ctx.takeStock(5, from: .base) { Ingredient(item: "wood", quantity: 1).matches($0) })
        XCTAssertEqual(took[made], 4)
        XCTAssertEqual(took[ProvenanceLedger.unknownOrigin], 1, "初期の 3 本のうち 1 本")
        XCTAssertNil(ctx.takeStock(99, from: .base) { _ in true })
    }

    /// 物質の条件で在庫を数える。
    func testMatterMatchCondition() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        ctx.addStock(.matter(Matter(substance: .iron, purity: Purity(percent: 90), stage: .metal, shape: .plate)), 2, to: .base)
        let fine = Condition.has(what: Ingredient(matter: MatterMatch(substance: .iron, shapes: [.plate], minPurity: Purity(percent: 85)), quantity: 2))
        let pure = Condition.has(what: Ingredient(matter: MatterMatch(substance: .iron, minPurity: Purity(percent: 98)), quantity: 1))
        XCTAssertEqual(ConditionEvaluator.evaluatePure(fine, world: ctx.world, content: rig.content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(pure, world: ctx.world, content: rig.content), false)
    }

    /// 置いた数の条件は、既定では建て終わった物だけを数える(組みかけの炉では試作できない)。
    func testPlacedCountIgnoresUnfinishedByDefault() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        let id = w.newEntityID()
        w.placements.items[id] = Placement(id: id, kind: .module("furnace"), at: w.map.spawn, facing: .north,
                                           origin: ProvenanceLedger.unknownOrigin, status: .underConstruction(progress: 0))
        let done = Condition.placedCount(module: "furnace", structure: nil, atLeast: 1)
        let any = Condition.placedCount(module: "furnace", structure: nil, atLeast: 1, includeUnfinished: true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(done, world: w, content: rig.content), false)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(any, world: w, content: rig.content), true)
        w.placements.items[id]?.status = .running
        XCTAssertEqual(ConditionEvaluator.evaluatePure(done, world: w, content: rig.content), true)
    }

    func testNearPlacementUsesRadiusCompletionAndTriggerPlacement() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let center = ctx.world.map.spawn
        let id = ctx.world.newEntityID()
        let record = ctx.record(.built, .structure("structure.storage", id), place: center)
        ctx.world.placements.items[id] = Placement(id: id, kind: .structure("structure.storage"), at: center,
                                                   facing: .north, origin: record, status: .running)
        let edge = Condition.nearPlacement(place: .point(at: WorldPoint(.surface, center.point + GridPoint(2, 2))),
                                           module: nil, structure: "structure.storage", radius: 2)
        let outside = Condition.nearPlacement(place: .point(at: WorldPoint(.surface, center.point + GridPoint(3, 0))),
                                              module: nil, structure: "structure.storage", radius: 2)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(edge, world: ctx.world, content: rig.content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(outside, world: ctx.world, content: rig.content), false)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.nearPlacement(place: .point(at: center), module: nil, structure: nil,
                                                                       radius: 0),
                                                  world: ctx.world, content: rig.content), true)

        ctx.world.placements.items[id]?.status = .underConstruction(progress: 0)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(edge, world: ctx.world, content: rig.content), false)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.nearPlacement(place: .placement(module: nil, structure: "structure.storage"),
                                                                       module: nil, structure: "structure.storage", radius: 0,
                                                                       includeUnfinished: true),
                                                  world: ctx.world, content: rig.content, trigger: record), true)
    }

    func testNearPlacementUsesPOIFootprintAtRadiusEdge() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        let anchor = GridPoint(4, 4)
        var layer = try XCTUnwrap(world.map[.surface])
        XCTAssertTrue(layer.placements.place(MapPlacement(id: "poi.test.near", kind: .wreck, templateID: "poi.test.near",
                                                           anchor: anchor, footprint: .rect(width: 2, height: 1),
                                                           entity: EntityID(9_001))))
        world.map[.surface] = layer

        let edge = Condition.nearPlacement(place: .point(at: WorldPoint(.surface, anchor + GridPoint(3, 0))),
                                           module: nil, structure: nil, poi: "poi.test.near", radius: 2)
        let outside = Condition.nearPlacement(place: .point(at: WorldPoint(.surface, anchor + GridPoint(4, 0))),
                                              module: nil, structure: nil, poi: "poi.test.near", radius: 2)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(edge, world: world, content: rig.content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(outside, world: world, content: rig.content), false)
    }

    /// 条件・効果の JSON は Swift の列挙の既定の形で書ける。
    func testConditionJSONShape() throws {
        let json = #"{"all": {"of": [{"known": {"expr": "fact.a"}}, {"ledger": {"query": {"act": "placed", "module": "furnace"}, "atLeast": 1}}]}}"#
        let c = try JSONDecoder().decode(Condition.self, from: Data(json.utf8))
        XCTAssertEqual(c, .all(of: [.known(expr: .fact("fact.a")), .ledger(query: ProvenanceQuery(act: .placed, module: "furnace"), atLeast: 1)]))
    }
}
