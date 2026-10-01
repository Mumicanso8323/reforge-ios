import RFContent
import RFKernel
import RFMatter
import RFPerception
import RFRules
import RFTestSupport
import RFWorld
import XCTest

final class PerceptionTests: XCTestCase {
    /// 遡る書き換え: 事実を知る前に持った物・置いた物も、知った瞬間に新しい名前で描かれる(保存は ID のまま)。
    func testFactRenamesExistingThingsRetroactively() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        // 置いた炉(事実を知る前)
        let id = w.newEntityID()
        w.placements.items[id] = Placement(id: id, kind: .module("furnace"), at: w.map.spawn, facing: .north,
                                           origin: ProvenanceLedger.unknownOrigin, status: .running)
        let before = Perceiver(content: rig.content, world: w)
        XCTAssertEqual(before.name(of: .item("test_ore")), "見慣れない石")
        XCTAssertEqual(before.name(Subject.module("furnace")), "炉")
        let saved = w

        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.revealed")
        w = ctx.world
        let after = Perceiver(content: rig.content, world: w)
        XCTAssertEqual(after.name(of: .item("test_ore")), "禁句Aの石")
        XCTAssertEqual(after.name(Subject.module("furnace")), "本当の炉")
        // 保存されている在庫と配置は同じ ID のまま(名前は保存していない)
        XCTAssertEqual(w.inventory, saved.inventory)
        XCTAssertEqual(w.placements, saved.placements)
    }

    /// 数値の見せ方も事実で切り替わる(段階の言葉 → 数)。隠れた値は出さない。
    func testStatDisplaySwitchesAndHiddenStaysHidden() throws {
        let db = try TestContent.publicOnly()
        XCTAssertEqual(Perceiver(content: db, known: []).stat("stat.test.air", value: Milli(raw: 950)), "濁っている")
        XCTAssertEqual(Perceiver(content: db, known: ["fact.test.revealed"]).stat("stat.test.air", value: Milli(raw: 950)), "95")
        XCTAssertNil(Perceiver(content: db, known: []).stat("stat.test.hidden", value: Milli(raw: 5)))
    }

    /// 物質の名前は部品ごとに引いて連結する。
    func testMatterNameFromParts() throws {
        let db = try TestContent.publicOnly()
        let m = Matter(substance: .iron, purity: Purity(percent: 90), stage: .metal, shape: .plate, temper: .hard)
        let name = Perceiver(content: db, known: []).name(of: .matter(m))
        XCTAssertTrue(name.contains("鉄") && name.contains("板") && name.contains("精"), name)
    }

    /// 見え方の無い見出し・文字列表に無いキーは英語の ID を出さない。
    func testUnknownSubjectNeverLeaksID() throws {
        let p = Perceiver(content: try TestContent.publicOnly(), known: [])
        XCTAssertEqual(p.name("item:no_such_thing"), "？")
        XCTAssertEqual(p.text("text.no_such_key"), "？")
    }

    /// 静的な監査: 公開の試験用コンテンツは全段で禁止語 0 件。
    func testPublicContentPassesAudit() throws {
        XCTAssertEqual(ForbiddenAudit.audit(try TestContent.publicOnly()), [])
    }

    /// 監査は、まだ知らない事実の語が出たら捕まえる(走行中の監査)。
    func testRuntimeCheckCatchesForbiddenWordAndEnglishID() throws {
        let db = try TestContent.publicOnly()
        XCTAssertEqual(ForbiddenAudit.check("禁句Aの石", content: db, known: []).count, 1)
        XCTAssertEqual(ForbiddenAudit.check("禁句Aの石", content: db, known: ["fact.test.revealed"]).count, 0)
        XCTAssertEqual(ForbiddenAudit.check("iron_ore", content: db, known: []).count, 1)
    }
}
