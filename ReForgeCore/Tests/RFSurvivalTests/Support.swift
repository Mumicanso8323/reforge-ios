import Foundation
import RFContent
import RFKernel
import RFRules
import RFSim
import RFSurvival
import RFTestSupport
import RFTime
import RFWorld
import RFFailure
import XCTest

/// 生存のテストの重ね(公開の試験用コンテンツの上に載せる)。公開の層そのものには生存の規則を入れない
/// (start に食料も水も無いので、入れると他の担当のテストで 3 日目に脱水の失敗が起きる)。
enum Fixture {
    static let survival = """
    {
      "survival": {
        "consumables": [
          { "item": "test.ration", "kind": "food" },
          { "item": "test.water_pack", "kind": "water" },
          { "item": "test.boiled_water", "kind": "water" },
          { "item": "test.raw_water", "kind": "water", "auto": false,
            "risk": { "basisPoints": 10000, "ailment": "ailment.test.poison", "severity": 1000, "body": { "mind": -2000 } } }
        ],
        "ailments": [
          { "id": "ailment.test.poison", "workPermille": 700, "bodyPerHour": { "health": -500 }, "recoveryPerDay": 1000 },
          { "id": "ailment.wound", "recoveryPerDay": 20 }
        ]
      },
      "skills": [ { "id": "skill.test.long", "hours": 1000 } ],
      "structures": [
        { "id": "structure.test.desk", "cost": [], "buildSeconds": 60, "provides": { "research": 1 } }
      ],
      "auras": [
        { "id": "aura.test.exhaust", "modifiers": [ { "bodyPerHour": { "stat": "mind", "amount": -1000 } } ] },
        { "id": "aura.test.extra", "modifiers": [ { "statPerHour": { "stat": "stat.test.gas.extra", "amount": 10 } } ] }
      ],
      "failureRules": [
        { "id": "failure.test.starve", "when": { "stat": { "id": "stat.days_without_food", "cmp": "ge", "value": 5000 } }, "cause": "text.test.starve" },
        { "id": "failure.test.thirst", "when": { "stat": { "id": "stat.days_without_water", "cmp": "ge", "value": 3000 } }, "cause": "text.test.thirst" }
      ]
    }
    """

    /// 拠点全体の数値の内訳と合計・暦・期限(生存の規則なし = 消費で失敗しない)。
    static let stats = """
    {
      "stats": [
        { "id": "stat.test.gas.base", "initial": 805, "perDay": 5 },
        { "id": "stat.test.gas.extra", "initial": 0 },
        { "id": "stat.test.gas", "initial": 805, "sumOf": ["stat.test.gas.base", "stat.test.gas.extra"],
          "marks": [1200, 1400, 1550], "alertAtLeast": 1400 },
        { "id": "stat.test.calendar", "initial": 339000, "perDay": 1000, "wrap": 340000 }
      ],
      "auras": [
        { "id": "aura.test.extra", "modifiers": [ { "statPerHour": { "stat": "stat.test.gas.extra", "amount": 10 } } ] }
      ],
      "failureRules": [
        { "id": "failure.test.deadline", "when": { "stat": { "id": "stat.test.gas", "cmp": "ge", "value": 1550 } }, "cause": "text.test.deadline" }
      ]
    }
    """

    static func content(_ overlays: String...) throws -> ContentDB {
        var db = try TestContent.publicOnly()
        for (i, o) in overlays.enumerated() { try ContentLoader.apply(json: Data(o.utf8), to: &db, name: "overlay\(i)") }
        return db
    }

    static func rig(_ overlays: String...) throws -> TestRig {
        var db = try TestContent.publicOnly()
        for (i, o) in overlays.enumerated() { try ContentLoader.apply(json: Data(o.utf8), to: &db, name: "overlay\(i)") }
        return TestRig(content: db)
    }
}

extension TestRig {
    /// 1 日(昼 + 夜)のステップ数。
    var stepsPerDay: Int { Int(TimeSystem.dayLength(content.clock).seconds / SimStep.gameSeconds) }
    var stepsPerHour: Int { Int(3600 / SimStep.gameSeconds) }
    /// 生存が体と数値を進める区切り 1 回ぶんのステップ数(既定 5 ゲーム分)。
    var stepsPerTick: Int { Int((content.survival?.tick ?? SurvivalDef.defaultTickSeconds) / SimStep.gameSeconds) }

    /// 拠点の蓄えに物を入れる。
    func stock(_ w: inout WorldState, _ item: ItemID, _ n: Int, to holder: HolderID = .base) {
        var ctx = StepContext(world: w, content: content)
        ctx.addStock(.item(item), n, to: holder)
        w = ctx.world
    }

    func count(_ w: WorldState, _ item: ItemID, in holder: HolderID = .base) -> Int {
        (w.inventory.holders[holder] ?? []).filter { $0.stuff == .item(item) }.reduce(0) { $0 + $1.quantity }
    }

    /// 建ち終えた建造物を置く(テスト用に直接)。
    func build(_ w: inout WorldState, _ kind: StructureKindID, at p: WorldPoint) -> EntityID {
        let id = w.newEntityID()
        w.placements.items[id] = Placement(id: id, kind: .structure(kind), at: p, facing: .south,
                                           origin: ProvenanceLedger.unknownOrigin, status: .running)
        return id
    }
}
