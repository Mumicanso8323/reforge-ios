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

/// P-13: 行為ごとの掘り出しの純度の上積み。鉱脈そのものは変えず、在庫に入る鉄鉱石の純度だけを変える。
final class ExtractPurityBonusTests: XCTestCase {
    static let dig: InteractionID = "interaction.mine_by_hand"

    /// 鉄 `fe`(万分率)と石英の脈石でできた鉱脈を、深さ 20(補正の無い段)に置く。
    func rig(bonus: Int?, fe: Int) throws -> (ExploreRig, GridPoint) {
        var r = try ExploreRig(seed: 7) { c in
            var def = c.interactions[Self.dig]!
            def.extractPurityBonus = bonus
            c.interactions[def.id] = def
        }
        let spot = r.noahPos.point + GridPoint(0, 1)
        let dep = Deposit(id: "deposit.test.fine", position: spot, category: .iron, appearanceVariant: 0,
                          composition: [DepositComponent(.fe, Purity(basisPoints: fe)),
                                        DepositComponent(.sio2, Purity(basisPoints: 10000 - fe))],
                          extractions: 20, depth: 20)
        _ = r.world.map[.surface]?.deposits.add(dep)
        return (r, spot)
    }

    func dig(bonus: Int?, fe: Int = 6000) throws -> ExploreRig {
        var (r, spot) = try rig(bonus: bonus, fe: fe)
        XCTAssertNil(r.interact(Self.dig, at: spot))
        return r
    }

    func orePurities(_ r: ExploreRig) -> [Int] {
        r.world.inventory.entries(.base).compactMap {
            if case .matter(let m) = $0.stuff, m.substance == .hematite { return m.purity.basisPoints }
            return nil
        }
    }

    func oreCount(_ r: ExploreRig) -> Int {
        r.world.inventory.quantity(where: { if case .matter = $0 { return true } else { return false } })
    }

    /// 欄が無い・0 は今までと同じ(世界の状態が一致する = 純度・数・乱数の消費)。
    func testNoBonusIsUnchanged() throws {
        let a = try dig(bonus: nil)
        let b = try dig(bonus: 0)
        XCTAssertEqual(orePurities(a), [6000])
        XCTAssertEqual(a.world, b.world)
    }

    func testBonusRaisesPurityOnly() throws {
        let a = try dig(bonus: nil)
        let b = try dig(bonus: 500)
        XCTAssertEqual(orePurities(a), [6000])
        XCTAssertEqual(orePurities(b), [6500])
        XCTAssertEqual(oreCount(a), oreCount(b))
        XCTAssertEqual(a.world.rng, b.world.rng)
        // 鉱脈そのものは変わらない
        XCTAssertEqual(a.world.map[.surface]?.deposits.all, b.world.map[.surface]?.deposits.all)
    }

    func testCapsAtFull() throws {
        let r = try dig(bonus: 500, fe: 9800)
        XCTAssertEqual(orePurities(r), [10000])
    }

    /// 純度を持たない物(脈石の石)は変わらない。
    func testItemsAreUnchanged() throws {
        let a = try dig(bonus: nil)
        let b = try dig(bonus: 500)
        XCTAssertGreaterThan(a.qty("stone"), 0)
        XCTAssertEqual(a.qty("stone"), b.qty("stone"))
    }

    func testCodableAndValidator() throws {
        let c = try TestContent.publicOnly()
        var def = c.interactions[Self.dig]!
        def.extractPurityBonus = 500
        let data = try JSONEncoder().encode(def)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"extractPurityBonus\":500"))
        XCTAssertEqual(try JSONDecoder().decode(InteractionDef.self, from: data).extractPurityBonus, 500)
        def.extractPurityBonus = nil
        let old = try JSONEncoder().encode(def)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("extractPurityBonus"))
        XCTAssertNil(try JSONDecoder().decode(InteractionDef.self, from: old).extractPurityBonus)

        for (v, bad) in [(10001, true), (-1, true), (0, false), (10000, false)] {
            var db = c
            var d = db.interactions[Self.dig]!
            d.extractPurityBonus = v
            db.interactions[d.id] = d
            let hit = ContentValidator.validate(db).contains { $0.level == .error && $0.rule == "interaction.extractPurityBonus" }
            XCTAssertEqual(hit, bad, "\(v)")
        }
    }
}
