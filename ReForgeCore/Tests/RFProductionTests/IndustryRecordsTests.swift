import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld
import XCTest

/// W-24 工業の「初めて」の記録(炉が熱に届いた・電気を出し始めた)。
final class IndustryRecordsTests: XCTestCase {
    typealias F = ProductionFixture
    static let hour: Int64 = 3600

    func records(_ w: WorldState, _ act: ActKind) -> [ProvenanceRecord] { w.ledger.records.filter { $0.act == act } }

    // MARK: 炉

    private func furnaceFixture() throws -> F {
        try F { c in
            c.modules[.furnace]?.hearth = HearthDef(capSeconds: 0, fuels: [:], thresholds: [0, 0, 0, 0],
                                                    light: [0, 0, 0, 0, 0], burnPermille: [0, 0, 0, 0, 0],
                                                    furnace: FurnaceHeatDef())
        }
    }

    private func furnaceLine(_ fx: F, _ w: inout WorldState) -> EntityID {
        F.addDeposit(&w, at: GridPoint(14, 16), percent: 30, extractions: 200)
        let d = fx.design([.minehead, .charcoalFurnace], &w)
        _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: F.wp(14, 16), facing: .east)), &w)
        _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: F.wp(15, 16), facing: .east)), &w)
        return w.placements.at(F.wp(15, 16))[0]
    }

    /// 予熱の途中は付かない。workTemp に届いたステップで furnace_hot と first_hot_furnace。冷えて予熱し直すと furnace_hot だけ。
    func testFurnaceReachingWorkTempRecordsHeatedOnceFirst() throws {
        let fx = try furnaceFixture()
        var w = fx.world(charcoal: 40)
        let furnace = furnaceLine(fx, &w)
        XCTAssertNil(fx.apply(.base(.hearth(placement: furnace, op: .preheat)), &w).rejection)
        _ = fx.run(seconds: 3600, &w)
        XCTAssertTrue(records(w, .heated).isEmpty, "予熱の途中")
        var events: [DomainEvent] = []
        events += fx.run(seconds: 1800, &w).events
        let first = records(w, .heated)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].tags, [IndustryRecords.furnaceHot, IndustryRecords.firstHotFurnace])
        XCTAssertEqual(first[0].subject, .module(.furnace, furnace))
        XCTAssertEqual(first[0].place, F.wp(15, 16))
        XCTAssertTrue(events.contains(.placementHeated(placement: furnace, record: first[0].id)))
        XCTAssertEqual(DomainEvent.placementHeated(placement: furnace, record: first[0].id).hook, "heated")
        // 熱いままの間は増えない
        _ = fx.run(seconds: 3 * Self.hour, &w)
        XCTAssertEqual(records(w, .heated).count, 1)

        // 木炭を取り上げて冷やし、予熱し直す
        w.inventory.holders[.base] = w.inventory.entries(.base).filter { $0.stuff != .item(.charcoal) }
        w.placements.items[furnace]?.module?.input.removeAll { $0.stuff == .item(.charcoal) }
        _ = fx.run(seconds: 8 * Self.hour, &w)
        XCTAssertLessThan(FurnaceHeat.temperature(w.placements.items[furnace]!, fx.content) ?? 9999, 1100)
        var ctx = StepContext(world: w, content: fx.content)
        ctx.addStock(.item(.charcoal), 10, to: .base)
        w = ctx.world
        XCTAssertNil(fx.apply(.base(.hearth(placement: furnace, op: .preheat)), &w).rejection)
        _ = fx.run(seconds: 5400, &w)
        let all = records(w, .heated)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].tags, [IndustryRecords.furnaceHot])
    }

    /// 熱の定義の無い炉(古い形の内容)では付かない。
    func testFurnaceWithoutHeatDefRecordsNothing() throws {
        let fx = try F()
        var w = fx.world(charcoal: 40)
        let furnace = furnaceLine(fx, &w)
        _ = fx.run(seconds: 9600 * 2, &w)
        XCTAssertNotNil(w.placements.items[furnace])
        XCTAssertTrue(records(w, .heated).isEmpty)
    }

    // MARK: 電気

    private static let overlay = """
    {
      "modules": [
        { "id": "test.generator", "cost": [ { "item": "wood", "quantity": 1 } ], "placement": {},
          "ports": [ { "side": "south", "flow": "input" } ], "cycleSeconds": 9600,
          "power": { "output": 100, "fuel": "charcoal", "fuelPerDay": 2 } },
        { "id": "test.sink", "cost": [ { "item": "wood", "quantity": 1 } ], "placement": {},
          "ports": [ { "side": "south", "flow": "input" } ], "cycleSeconds": 9600,
          "power": { "draw": 10 } }
      ],
      "structures": [
        { "id": "test.dynamo", "cost": [], "buildSeconds": 1, "provides": { "power": 5 }, "requiresBaseArea": false },
        { "id": "test.fire_dynamo", "cost": [], "buildSeconds": 1, "provides": { "power": 3 }, "requiresBaseArea": false,
          "whenLit": 1,
          "hearth": { "capSeconds": 43200, "fuels": { "wood": 21600 }, "thresholds": [0, 10800, 21600, 32400],
                      "light": [0, 2, 3, 4, 5], "burnPermille": [0, 500, 750, 1000, 1500] } },
        { "id": "test.lamp", "cost": [], "buildSeconds": 1, "provides": { "light": 3 }, "requiresBaseArea": false }
      ]
    }
    """

    private func powerFixture() throws -> F {
        try F { db in try ContentLoader.apply(json: Data(Self.overlay.utf8), to: &db, name: "w24.power") }
    }

    /// 発電機が動き出すと powered と first_power。燃料が切れて止まり、補給して動くと 2 回目は powered だけ。
    func testGeneratorRecordsPoweredAndFirstPowerOnce() throws {
        let fx = try powerFixture()
        var w = fx.world(charcoal: 2)
        w.research.unlocked.modules.formUnion(["test.generator", "test.sink"])
        let gen = fx.place("test.generator", 13, 15, &w)
        _ = fx.run(seconds: 60, &w)
        let first = records(w, .powered)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].tags, [IndustryRecords.powered, IndustryRecords.firstPower])
        XCTAssertEqual(first[0].subject, .module("test.generator", gen))
        // 動き続けている間は増えない
        _ = fx.run(seconds: 600, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
        // 燃料が切れる → 止まる
        let day = Int64(fx.content.clock.dayGameSeconds + fx.content.clock.nightGameSeconds)
        _ = fx.run(seconds: day * 2, &w)
        XCTAssertNotEqual(w.placements.items[gen]?.status, .running)
        XCTAssertEqual(records(w, .powered).count, 1)
        var ctx = StepContext(world: w, content: fx.content)
        ctx.addStock(.item(.charcoal), 5, to: .base)
        w = ctx.world
        _ = fx.run(seconds: 600, &w)
        let all = records(w, .powered)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].tags, [IndustryRecords.powered])
    }

    /// 電気を出さない(出力 0・power を持たない)モジュールでは付かない。
    func testModulesThatDoNotProducePowerRecordNothing() throws {
        let fx = try powerFixture()
        var w = fx.world()
        w.research.unlocked.modules.formUnion(["test.generator", "test.sink"])
        _ = fx.place("test.sink", 13, 15, &w)
        _ = fx.place(.millstone, 16, 16, &w)
        _ = fx.run(seconds: 600, &w)
        XCTAssertTrue(records(w, .powered).isEmpty)
    }

    private func structure(_ kind: StructureKindID, _ x: Int, status: PlacementStatus, _ w: inout WorldState) -> EntityID {
        let id = w.newEntityID()
        var p = Placement(id: id, kind: .structure(kind), at: F.wp(x, 16), facing: .north, origin: ProvenanceID(0), status: status)
        p.structure = StructureRuntime()
        w.placements.items[id] = p
        return id
    }

    /// 電気を出す建造物は、建ち終わったステップに記録される(建造中は付かない)。出さない建造物では付かない。
    func testStructureRecordsPoweredWhenBuilt() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let dynamo = structure("test.dynamo", 12, status: .underConstruction(progress: 0), &w)
        _ = structure("test.lamp", 14, status: .running, &w)
        _ = fx.run(seconds: 60, &w)
        XCTAssertTrue(records(w, .powered).isEmpty, "建造中と電気を出さない物")
        w.placements.items[dynamo]?.status = .running
        let r = fx.run(seconds: 60, &w)
        let recs = records(w, .powered)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].tags, [IndustryRecords.powered, IndustryRecords.firstPower])
        XCTAssertEqual(recs[0].subject, .structure("test.dynamo", dynamo))
        XCTAssertTrue(r.events.contains(.placementPowered(placement: dynamo, record: recs[0].id)))
        _ = fx.run(seconds: 600, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
        // 壊れて直ると、また働き始める(2 回目は powered だけ)
        w.placements.items[dynamo]?.status = .broken
        _ = fx.run(seconds: 60, &w)
        w.placements.items[dynamo]?.status = .running
        _ = fx.run(seconds: 60, &w)
        let all = records(w, .powered)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].tags, [IndustryRecords.powered])
    }

    // MARK: 条件

    /// firstTime と ledger の条件で引ける。保存の形は変わらない(ActKind は名前で持つ)。
    func testConditionsQueryNewTagsAndActs() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let dynamo = structure("test.dynamo", 12, status: .running, &w)
        _ = fx.run(seconds: 60, &w)
        let rec = try XCTUnwrap(records(w, .powered).first)
        let firstTime = Condition.firstTime(query: ProvenanceQuery(act: .powered))
        XCTAssertEqual(ConditionEvaluator.evaluatePure(firstTime, world: w, content: fx.content, trigger: rec.id), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(
            .ledger(query: ProvenanceQuery(tag: IndustryRecords.firstPower), atLeast: 1), world: w, content: fx.content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(
            .ledger(query: ProvenanceQuery(tag: IndustryRecords.firstHotFurnace), atLeast: 1), world: w, content: fx.content),
            false)
        XCTAssertNotNil(w.placements.items[dynamo])
        XCTAssertEqual(ActKind(rawValue: "heated"), .heated)
        XCTAssertEqual(ActKind(rawValue: "powered"), .powered)
        XCTAssertEqual(IndustryRecords.firstPower.rawValue, "tag.invention.first_power")
        XCTAssertEqual(IndustryRecords.firstHotFurnace.rawValue, "tag.invention.first_hot_furnace")
    }

    // MARK: 保存・取り消し

    private func roundTrip(_ w: WorldState) throws -> WorldState {
        try JSONDecoder().decode(WorldState.self, from: try JSONEncoder().encode(w))
    }

    /// 保存して読み直しても、働いている建造物・発電機は二重に記録しない。
    func testSaveAndReloadDoesNotDoubleRecord() throws {
        let fx = try powerFixture()
        var w = fx.world(charcoal: 40)
        w.research.unlocked.modules.formUnion(["test.generator"])
        _ = structure("test.dynamo", 12, status: .running, &w)
        _ = fx.place("test.generator", 13, 15, &w)
        _ = fx.run(seconds: 600, &w)
        XCTAssertEqual(records(w, .powered).count, 2)
        var loaded = try roundTrip(w)
        XCTAssertEqual(loaded, w)
        _ = fx.run(seconds: 600, &loaded)
        XCTAssertEqual(records(loaded, .powered).count, 2)
    }

    /// 古い保存(印のキーが無い)で既に記録のある建造物は、読んだ後に二重に記録しない。止まった後の再開は記録する。
    func testOldSaveWithoutMarkerDoesNotDoubleRecord() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let dynamo = structure("test.dynamo", 12, status: .running, &w)
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
        var old = w
        old.placements.items[dynamo]?.structure?.parameters["powered"] = nil
        _ = fx.run(seconds: 60, &old)
        XCTAssertEqual(records(old, .powered).count, 1, "印だけ付け直す")
        XCTAssertEqual(old.placements.items[dynamo]?.structure?.parameters["powered"], 1)
        old.placements.items[dynamo]?.status = .broken
        _ = fx.run(seconds: 60, &old)
        old.placements.items[dynamo]?.status = .running
        _ = fx.run(seconds: 60, &old)
        XCTAssertEqual(records(old, .powered).count, 2, "止まった後の再開は記録する")
    }

    /// 取り消し(世界の写しに戻す)の後に同じ時間を進めても、記録は写しの時点から 1 回だけ。
    func testRestoringSnapshotDoesNotDoubleRecord() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let dynamo = structure("test.dynamo", 12, status: .underConstruction(progress: 0), &w)
        _ = fx.run(seconds: 60, &w)
        let snapshot = w
        w.placements.items[dynamo]?.status = .running
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
        w = snapshot
        XCTAssertTrue(records(w, .powered).isEmpty)
        w.placements.items[dynamo]?.status = .running
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
    }

    /// 保存の形: 印は建造物の parameters の 1 キーだけで、版は上がらない。電気を出さない建造物には付かない。
    func testSaveShapeAddsOnlyMarkerKey() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let dynamo = structure("test.dynamo", 12, status: .running, &w)
        let lamp = structure("test.lamp", 14, status: .running, &w)
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(w.placements.items[dynamo]?.structure?.parameters, ["powered": 1])
        XCTAssertEqual(w.placements.items[lamp]?.structure?.parameters, [:])
        XCTAssertNil(w.placements.items[dynamo]?.structure?.durability)
    }

    /// whenLit の建造物は、火が点いて効いている間だけ働く。消えて点け直すと 2 回目(powered だけ)。
    func testStructureWhenLitTransitions() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let id = structure("test.fire_dynamo", 12, status: .running, &w)
        w.placements.items[id]?.structure?.hearth = HearthState(fuel: 0, lit: false)
        _ = fx.run(seconds: 60, &w)
        XCTAssertTrue(records(w, .powered).isEmpty, "火が消えている間は働かない")
        w.placements.items[id]?.structure?.hearth = HearthState(fuel: 30_000_000, lit: true)
        _ = fx.run(seconds: 60, &w)
        var recs = records(w, .powered)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].tags, [IndustryRecords.powered, IndustryRecords.firstPower])
        _ = fx.run(seconds: 300, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
        w.placements.items[id]?.structure?.hearth = HearthState(fuel: 0, lit: false)
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(w.placements.items[id]?.structure?.parameters["powered"], 0)
        w.placements.items[id]?.structure?.hearth = HearthState(fuel: 30_000_000, lit: true)
        _ = fx.run(seconds: 60, &w)
        recs = records(w, .powered)
        XCTAssertEqual(recs.count, 2)
        XCTAssertEqual(recs[1].tags, [IndustryRecords.powered])
    }

    /// 古い保存(印が無い)で止まっている建造物は 0 を付けられ、最初に動き直した時に記録される。
    func testOldSaveStoppedStructureRecordsWhenItResumes() throws {
        let fx = try powerFixture()
        var w = fx.world()
        let dynamo = structure("test.dynamo", 12, status: .running, &w)
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(records(w, .powered).count, 1)
        w.placements.items[dynamo]?.status = .broken
        w.placements.items[dynamo]?.structure?.parameters["powered"] = nil
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(w.placements.items[dynamo]?.structure?.parameters["powered"], 0)
        w.placements.items[dynamo]?.status = .running
        _ = fx.run(seconds: 60, &w)
        XCTAssertEqual(records(w, .powered).count, 2)
    }
}
