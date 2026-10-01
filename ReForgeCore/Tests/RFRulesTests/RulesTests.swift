import RFContent
import RFKernel
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

    /// 条件・効果の JSON は Swift の列挙の既定の形で書ける。
    func testConditionJSONShape() throws {
        let json = #"{"all": {"of": [{"known": {"expr": "fact.a"}}, {"ledger": {"query": {"act": "placed", "module": "furnace"}, "atLeast": 1}}]}}"#
        let c = try JSONDecoder().decode(Condition.self, from: Data(json.utf8))
        XCTAssertEqual(c, .all(of: [.known(expr: .fact("fact.a")), .ledger(query: ProvenanceQuery(act: .placed, module: "furnace"), atLeast: 1)]))
    }
}
