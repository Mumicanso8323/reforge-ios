import Foundation
import RFContent
import RFKernel
import RFMap
import RFPerception
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U19 の受け入れテスト(opening v0.2 §10): 暗闇でも描く光る印(glow)・部品の地図の文字・遠景(landmarkRadius)・
/// 資料の段(修理の段階で本文と読める割合を選ぶ)。
final class DepthHintPresentTests: XCTestCase {
    static let kind: POIKindID = "poi.test.wreck"

    func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func content(landmark: Int? = nil) throws -> ContentDB {
        var c = try TestContent.publicOnly()
        let lr = landmark.map { ",\"landmarkRadius\":\($0)" } ?? ""
        c.pois[Self.kind] = try decode(
            "{\"id\":\"\(Self.kind.rawValue)\",\"parts\":[\"part.test.a\",\"part.test.b\"],\"parameters\":null\(lr)}")
        c.texts["text.test.part_a"] = "試験の部品"
        c.perception[Subject.part("part.test.a")] = SubjectDef(subject: Subject.part("part.test.a"), variants: [
            Variant(when: .always, name: "text.test.part_a", glyph: "▣", glow: true),
        ])
        return c
    }

    func world(_ c: ContentDB) -> WorldState {
        var w = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: 1)
        _ = w.map[.surface]!.placements.place(MapPlacement(id: "poi.test", kind: .wreck, templateID: Self.kind.rawValue,
                                                           anchor: GridPoint(3, 3), footprint: .rect(width: 2, height: 1),
                                                           entity: EntityID(900)))
        return w
    }

    func know(_ w: inout WorldState, _ pts: [GridPoint]) {
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        for p in pts { bits[p] = true }
        w.knowledge.mapKnown[.surface] = bits
    }

    // MARK: glow と部品の文字(HNT-01・HNT-02・TEST-O8 の本体側)

    func testPartGlyphAndGlowOnKnownTile() throws {
        let c = try content()
        let b = FrameBuilder(content: c)
        var w = world(c)
        XCTAssertFalse(b.tile(w, at: GridPoint(3, 3)).glow, "未踏のマスの光は描かない")
        know(&w, [GridPoint(3, 3), GridPoint(4, 3)])
        let a = b.tile(w, at: GridPoint(3, 3))
        XCTAssertEqual(a.glyph, MapGlyphFont.safe("▣"), "部品の見え方の文字が地図の字になる")
        XCTAssertTrue(a.glow, "暗闇でも描く光る印")
        let other = b.tile(w, at: GridPoint(4, 3))
        XCTAssertFalse(other.glow, "見え方の無い部品は POI の見え方のまま")
        XCTAssertNotEqual(other.glyph, MapGlyphFont.safe("▣"))
    }

    // MARK: 遠景(HNT-11)

    func testLandmarkRadiusShowsShadowFromFar() throws {
        for (radius, expectHint) in [(nil, false), (6, true)] as [(Int?, Bool)] {
            let c = try content(landmark: radius)
            let b = FrameBuilder(content: c)
            var w = world(c)
            w.people[.noah]!.position = WorldPoint(.surface, GridPoint(30, 30))
            know(&w, [GridPoint(3, 8)])  // 5 マス先だけ知っている
            let t = b.tile(w, at: GridPoint(3, 3))
            XCTAssertEqual(t.fog == .hint, expectHint, "半径 \(String(describing: radius))")
            if expectHint {
                XCTAssertNotEqual(t.shadow, "？", "遠景は起点も目印の影")
                XCTAssertNotNil(t.shadow)
            }
        }
    }

    // MARK: 資料の段(HNT-04・HNT-12)

    func testDocumentStageFollowsRepairStage() throws {
        var c = try content()
        c.texts["text.test.doc.title"] = "試験の資料"
        c.texts["text.test.doc.body0"] = "■■■"
        c.texts["text.test.doc.body1"] = "読める■"
        c.documents["doc.test.staged"] = DocumentDef(
            id: "doc.test.staged", title: "text.test.doc.title", body: "text.test.doc.body0", when: .always,
            stages: DocumentStages(poiKind: Self.kind, part: "part.test.a", steps: [
                DocumentStep(atLeast: 0, readablePermille: 40),
                DocumentStep(atLeast: 1, body: "text.test.doc.body1", readablePermille: 350),
            ]))
        let b = FrameBuilder(content: c)
        var w = world(c)
        let p0 = try XCTUnwrap(b.document("doc.test.staged", in: w))
        XCTAssertEqual(p0.body, "■■■")
        XCTAssertEqual(p0.readablePermille, 40)
        XCTAssertEqual(p0.repairStage, 0)
        w.exploration.poi[EntityID(900), default: POIProgress()].repair["part.test.a"] = 1
        XCTAssertEqual(RepairStage.of(poiKind: Self.kind, part: "part.test.a", in: w), 1)
        let p1 = try XCTUnwrap(b.document("doc.test.staged", in: w))
        XCTAssertEqual(p1.body, "読める■")
        XCTAssertEqual(p1.readablePermille, 350)
        // 条件からも引ける
        XCTAssertEqual(ConditionEvaluator.evaluatePure(
            .poi(kind: Self.kind, test: .repairAtLeast(part: "part.test.a", stage: 1)), world: w, content: c), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(
            .poi(kind: Self.kind, test: .repairAtLeast(part: "part.test.a", stage: 2)), world: w, content: c), false)
    }

    /// 段の無い資料は今までどおり(読める割合を出さない)。
    func testDocumentWithoutStagesUnchanged() throws {
        var c = try content()
        c.texts["text.test.doc.title"] = "試験の資料"
        c.texts["text.test.doc.body0"] = "本文"
        c.documents["doc.test.plain"] = DocumentDef(id: "doc.test.plain", title: "text.test.doc.title",
                                                    body: "text.test.doc.body0", when: .always)
        let p = try XCTUnwrap(FrameBuilder(content: c).document("doc.test.plain", in: world(c)))
        XCTAssertEqual(p.body, "本文")
        XCTAssertNil(p.readablePermille)
    }
}
