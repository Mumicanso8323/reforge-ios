import Foundation
import RFContent
import RFKernel
import RFMap
import RFPresent
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U18(opening §10 の画面側): 帯の目盛り・残骸から開く資料・研究の残りの数・建てる一覧の「？」。
final class HintScreenPresentTests: XCTestCase {
    static let kind: POIKindID = "poi.test.wreck18"

    func testGaugeScalesMarksWithoutMeaning() throws {
        let g = try XCTUnwrap(StatGauge.make(value: 500, marks: [1000, 300, 600]))
        XCTAssertEqual(g.marks, [272, 545, 909], "昇順・一番上の目盛りは右端の手前")
        XCTAssertEqual(g.fillPermille, 454)
        XCTAssertNil(StatGauge.make(value: 1, marks: []))
        XCTAssertEqual(StatGauge.make(value: 99_999, marks: [10])?.fillPermille, 1000)
    }

    func testStatusItemShowsMarksOnlyWhenTheVariantAsks() throws {
        var c = try TestContent.publicOnly()
        c.stats["stat.test.gas"] = StatDef(id: "stat.test.gas", initial: 200, marks: [400, 800])
        c.texts["text.test.gas"] = "ガス"
        let display = StatDisplay.number(divisor: 10, unit: nil)
        c.perception[Subject.stat("stat.test.gas")] = SubjectDef(subject: Subject.stat("stat.test.gas"), variants: [
            Variant(when: .always, name: "text.test.gas", display: display),
        ])
        var w = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: 1)
        w.survival.stats["stat.test.gas"] = Milli(raw: 200)
        let b = FrameBuilder(content: c)
        let item = { b.build(w, revision: 0, previous: nil, report: nil).status.first { $0.key == "stat.test.gas" } }
        XCTAssertNotNil(item())
        XCTAssertNil(item()?.gauge, "指定が無ければ数だけ")
        c.perception[Subject.stat("stat.test.gas")] = SubjectDef(subject: Subject.stat("stat.test.gas"), variants: [
            Variant(when: .always, name: "text.test.gas", display: display, showMarks: true),
        ])
        let b2 = FrameBuilder(content: c)
        let g = try XCTUnwrap(b2.build(w, revision: 0, previous: nil, report: nil).status.first { $0.key == "stat.test.gas" }?.gauge)
        XCTAssertEqual(g.marks.count, 2)
        XCTAssertGreaterThan(g.fillPermille, 0)
    }

    func testFootCardOffersTheStagedDocumentOfTheWreck() throws {
        var c = try TestContent.publicOnly()
        c.pois[Self.kind] = try JSONDecoder().decode(POIDef.self, from: Data(
            "{\"id\":\"\(Self.kind.rawValue)\",\"parts\":[\"part.test.a\"],\"parameters\":null}".utf8))
        c.texts["text.test.panel"] = "試験の端末"
        c.documents["doc.test.panel"] = DocumentDef(
            id: "doc.test.panel", title: "text.test.panel", body: "text.unknown", when: .always,
            stages: DocumentStages(poiKind: Self.kind, part: "part.test.a", steps: [DocumentStep(atLeast: 0, readablePermille: 40)]))
        c.documents["doc.test.other"] = DocumentDef(id: "doc.test.other", title: "text.test.panel", body: "text.unknown",
                                                    when: .always)
        var w = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: 1)
        _ = w.map[.surface]!.placements.place(MapPlacement(id: "poi.test18", kind: .wreck, templateID: Self.kind.rawValue,
                                                           anchor: GridPoint(3, 3), footprint: .rect(width: 1, height: 1),
                                                           entity: EntityID(901)))
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        bits[GridPoint(3, 3)] = true
        w.knowledge.mapKnown[.surface] = bits
        let b = FrameBuilder(content: c)
        let card = try XCTUnwrap(b.footCard(w, at: GridPoint(3, 3)))
        XCTAssertEqual(card.documents.map(\.id), ["doc.test.panel"], "段のある資料だけ、その残骸から開ける")
        XCTAssertEqual(card.documents.first?.title, "試験の端末")
        XCTAssertEqual(b.document("doc.test.panel", in: w)?.readablePermille, 40)
        XCTAssertEqual(b.footCard(w, at: GridPoint(10, 10))?.documents ?? [], [])
    }

    func testPortraitFollowsTheVariantAndIDsStayNeutral() throws {
        var c = try TestContent.publicOnly()
        let noah = Subject.person(.noah)
        var def = try XCTUnwrap(c.perception[noah])
        def.variants[def.variants.count - 1].art = "art.person.001"
        c.perception[noah] = def
        let w = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: 1)
        XCTAssertEqual(FrameBuilder(content: c).crew(w).members.first { $0.isNoah }?.art, "art.person.001")
        XCTAssertEqual(ContentValidator.validate(c).filter { $0.rule == "perception.art" }, [])
        def.variants[def.variants.count - 1].art = "Art Person"
        c.perception[noah] = def
        XCTAssertEqual(ContentValidator.validate(c).filter { $0.rule == "perception.art" }.count, 1)
        XCTAssertNil(FrameBuilder(content: try TestContent.publicOnly()).crew(w).members.first?.art, "絵が無ければ nil")
    }

    func testResearchHiddenCountAndUnknownStructures() throws {
        let rig = try TestRig.publicOnly()
        let w = rig.factory.newWorld(seed: 1)
        let b = FrameBuilder(content: rig.content)
        let r = b.research(w)
        XCTAssertEqual(r.entries.count + r.hiddenCount, rig.content.research.count, "見える + 見えない = 全部")
        let base = b.base(w)
        XCTAssertEqual(base.buildable.count <= w.research.unlocked.structures.count, true)
        XCTAssertEqual(base.unknownStructures + base.shadows.count,
                       rig.content.structures.keys.filter { !w.research.unlocked.structures.contains($0) }.count,
                       "「？」の数 = 未解放 − 影")
        XCTAssertTrue(base.shadows.allSatisfy { if case .structure = $0.kind { true } else { false } })
    }
}
