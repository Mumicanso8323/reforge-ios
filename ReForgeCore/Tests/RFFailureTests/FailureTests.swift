import RFContent
import RFFailure
import RFKernel
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class FailureTests: XCTestCase {
    /// 失敗の規則(値で判定)が成り立つと周回が失敗になり、本体は進まなくなる。
    func testFailureRuleEndsRun() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        w.narrative.counters["counter.test.doom"] = 1
        let r = rig.simulation.runSteps(3, &w)
        XCTAssertEqual(r.steps, 1)
        XCTAssertEqual(w.run.outcome, .failed(cause: "text.test.cause", record: w.ledger.records.last?.id))
        XCTAssertNotNil(rig.simulation.apply(.time(.sleep), to: &w).rejection)
    }

    /// 記憶を持って巻き戻す: 在庫・配置・生死は夜明けに戻り、知った事実(記憶)・ノート・地図の既知・関係・
    /// 残る記憶は持ち越す。その時間軸だけの事実は消える。来歴の番号は前の周回の続きから。
    func testRewindCarriesMemoryNotMatter() throws {
        let rig = try TestRig.publicOnly()
        let dawn = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: dawn, content: rig.content)
        ctx.learn("fact.test.revealed")
        ctx.learn("fact.test.timeline")
        ctx.addStock(.item("wood"), 50, to: .base)
        ctx.world.people["person.test_a"]?.relation.points = 40
        ctx.world.people["person.test_a"]?.relation.rank = 2
        ctx.world.people["person.test_a"]?.memories.append(
            MemoryRecord(kind: "memory.test.saw", at: .zero, run: 1, about: nil, persistsAcrossRewind: true))
        ctx.world.people["person.test_b"]?.presence = .dead(at: .zero, record: nil)
        let memorable = ctx.record(.died, .person("person.test_b"), tags: ["tag.test.memorable"])
        ctx.world.knowledge.mapKnown[.surface] = {
            var b = GridBitset(size: GridSize(width: 32, height: 32))
            b[GridPoint(1, 1)] = true
            return b
        }()
        ctx.world.run.outcome = .failed(cause: "text.test.cause", record: nil)
        let failed = ctx.world

        let w = MemoryCarry.rewind(failed: failed, dawn: dawn, content: rig.content)
        XCTAssertTrue(w.knowledge.knows("fact.test.revealed"))
        XCTAssertFalse(w.knowledge.knows("fact.test.timeline"))
        XCTAssertEqual(w.inventory, dawn.inventory)
        XCTAssertTrue(w.people["person.test_b"]?.presence.isAlive == true, "生死は夜明けに戻る")
        XCTAssertEqual(w.people["person.test_a"]?.relation.points, 40)
        XCTAssertEqual(w.people["person.test_a"]?.memories.count, 1)
        XCTAssertTrue(w.knowledge.mapKnown[.surface]?[GridPoint(1, 1)] == true)
        XCTAssertEqual(w.run.index, 2)
        XCTAssertEqual(w.run.pastLives.first?.memorable.map(\.id), [memorable])
        XCTAssertTrue(w.run.isActive)
        var after = StepContext(world: w, content: rig.content)
        XCTAssertGreaterThan(after.record(.rewound, .none), memorable)
    }
}
