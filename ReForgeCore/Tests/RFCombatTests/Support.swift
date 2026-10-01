import Foundation
import RFCombat
import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// RFCombat のテストの道具。公開の試験用コンテンツ(content/public/combat/combat.json)に、試験ごとの上書きを重ねる。
enum Fixture {
    /// 夜の群れ: 小さい獣 2 匹が毎晩必ず来る(日没の 1〜2 時間後)。
    static let nightlyRaid = """
    {"enemies": [{"id": "enemy.test.small", "health": 15, "attack": 3, "defense": 1, "speed": 5,
      "drops": [{"item": "test_meat", "min": 1, "max": 1}], "steals": [{"item": "test_stash", "quantity": 1}],
      "tags": ["tag.test.hunt"], "raid": {"perNight": 10000, "min": 2, "max": 2}}]}
    """

    /// 森で出会う群れ(1 時間に 1 度は出会う)。
    static let forestPack = """
    {"enemies": [{"id": "enemy.test.pack", "health": 35, "attack": 8, "defense": 3, "speed": 7, "mapSpeed": 6,
      "drops": [{"item": "test_meat", "min": 2, "max": 2}], "nocturnal": false,
      "habitats": ["forest"], "encounterPerHour": 10000, "tags": ["tag.test.hunt"]}]}
    """

    static func rig(_ overrides: String...) throws -> TestRig {
        var db = try TestContent.publicOnly()
        for (i, o) in overrides.enumerated() { try ContentLoader.apply(json: Data(o.utf8), to: &db, name: "override-\(i)") }
        return TestRig(content: db)
    }

    /// 獣が狙う場所(試験の平らな地図では拠点の中心 16,16)。
    static let store = GridPoint(16, 16)
    static func at(_ p: GridPoint) -> WorldPoint { WorldPoint(.surface, p) }

    /// 人を地図から外す(戦えない)。
    static func clearPeople(_ w: inout WorldState, except keep: [PersonID] = []) {
        for p in w.people.order where !keep.contains(p) { w.people[p]?.position = nil }
    }

    /// 獣が狙う蓄え(試験では生存の担当が食べない別の品にして、奪われた分だけが減るようにする)。
    static func addFood(_ w: inout WorldState, _ n: Int) {
        w.inventory.holders[.base, default: []].append(StockEntry(stuff: .item("test_stash"), quantity: n))
    }

    static func food(_ w: WorldState) -> Int { w.inventory.quantity("test_stash") }

    /// 完成した建造物を置く(拠点の担当のコマンドの代わり)。
    @discardableResult
    static func build(_ w: inout WorldState, _ kind: StructureKindID, at p: GridPoint) -> EntityID {
        let id = w.newEntityID()
        let rec = w.ledger.append {
            ProvenanceRecord(id: $0, at: w.clock.now, day: w.clock.day, run: w.run.index, actor: .noah, act: .built,
                             subject: .structure(kind, id), place: at(p))
        }
        w.placements.items[id] = Placement(id: id, kind: .structure(kind), at: at(p), facing: .north, origin: rec,
                                           status: .running)
        return id
    }

    /// 槍(棒の形の鉄)を持たせる。
    static func arm(_ w: inout WorldState, _ p: PersonID, purity: Int = 7000, temper: Temper = .hard, shape: Shape = .rod) {
        let m = Matter(substance: .iron, purity: Purity(basisPoints: purity), stage: .metal, shape: shape, worked: 1,
                       temper: temper)
        let rec = w.ledger.append {
            ProvenanceRecord(id: $0, at: w.clock.now, day: w.clock.day, run: w.run.index, actor: p, act: .crafted,
                             subject: .matter(NameGenerator.name(for: m)))
        }
        w.people[p]?.equipment["weapon"] = EquippedItem(stuff: .matter(m), origin: rec)
    }

    /// 日没まで進める。
    static func toDusk(_ rig: TestRig, _ w: inout WorldState) -> StepReport { rig.playDay(&w, dt: 1) }

    /// 夜明けまで 1 ステップずつ進め、毎ステップ check を呼ぶ。
    static func throughNight(_ rig: TestRig, _ w: inout WorldState, check: (WorldState) -> Void = { _ in }) -> StepReport {
        var r = StepReport()
        var n = 0
        while w.clock.phase != .day && n < 10_000 {
            r.merge(rig.simulation.runSteps(1, &w))
            check(w)
            n += 1
        }
        return r
    }

    /// 戦闘が全部終わるまで(上限つき)進める。
    static func untilBattlesEnd(_ rig: TestRig, _ w: inout WorldState, maxSteps: Int = 5000) -> StepReport {
        var r = StepReport()
        var n = 0
        repeat {
            r.merge(rig.simulation.runSteps(1, &w))
            n += 1
        } while !w.combat.battles.isEmpty && n < maxSteps
        return r
    }

    static func ended(_ events: [DomainEvent]) -> [(EntityID, Bool, Bool, ProvenanceID)] {
        events.compactMap { if case .battleEnded(let b, let won, let fled, let r) = $0 { (b, won, fled, r) } else { nil } }
    }

    static func started(_ events: [DomainEvent]) -> [EntityID] {
        events.compactMap { if case .battleStarted(let b, _) = $0 { b } else { nil } }
    }
}
