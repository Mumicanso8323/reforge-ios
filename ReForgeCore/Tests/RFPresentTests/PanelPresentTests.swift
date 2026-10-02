import Foundation
import RFContent
import RFKernel
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U18: 画面の要素の解放・拠点・仲間・研究・戦闘の射影。
final class PanelPresentTests: XCTestCase {
    var rig: TestRig!

    override func setUpWithError() throws { rig = try TestRig.publicOnly() }

    func world() -> WorldState { rig.factory.newWorld(seed: 1) }

    func gatedContent() throws -> ContentDB {
        var db = rig.content
        db.interactions.removeAll()
        let json = """
        {
          "interactions": [
            { "id": "interaction.test.ui.pick", "target": { "terrain": { "tag": "ground" } }, "seconds": 30,
              "hold": false, "yields": [] },
            { "id": "interaction.test.ui.later", "target": { "terrain": { "tag": "ground" } }, "seconds": 30,
              "hold": false, "yields": [] }
          ],
          "uiGates": [
            { "id": "tab.base", "when": { "known": { "expr": "fact.test.alpha" } } },
            { "id": "interaction.interaction.test.ui.later", "when": { "known": { "expr": "fact.test.alpha" } } }
          ]
        }
        """
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        return db
    }

    func testGatesOpenWhenConditionHoldsAndUngatedAlwaysOpen() throws {
        let b = FrameBuilder(content: try gatedContent())
        var w = world()
        let f = b.build(w, revision: 0, previous: nil, report: nil)
        XCTAssertFalse(f.ui.isOpen(UIUnlocks.Element.tabBase))
        XCTAssertTrue(f.ui.isOpen(UIUnlocks.Element.tabCrew), "表に無い要素は出す")
        XCTAssertTrue(f.ui.isOpen("design.sheet"))
        let pt = GridPoint(16, 17)
        XCTAssertEqual(b.footCard(w, at: pt)?.actions.map(\.id.rawValue), ["interaction.test.ui.pick"],
                       "足元の札の行為も条件で絞る")

        var ctx = StepContext(world: w, content: b.content)
        ctx.learn("fact.test.alpha")
        w = ctx.world
        XCTAssertTrue(b.build(w, revision: 1, previous: nil, report: nil).ui.isOpen(UIUnlocks.Element.tabBase))
        XCTAssertEqual(b.footCard(w, at: pt)?.actions.count, 2)
    }

    func testValidatorChecksGateIDs() throws {
        var db = try gatedContent()
        XCTAssertEqual(ContentValidator.validate(db).filter { $0.rule.hasPrefix("uiGates") }, [])
        db.uiGates["tab.nothing"] = UIGateDef(id: "tab.nothing", when: .always)
        db.uiGates["interaction.interaction.test.ui.missing"] = UIGateDef(id: "interaction.interaction.test.ui.missing",
                                                                          when: .always)
        XCTAssertEqual(ContentValidator.validate(db).filter { $0.rule == "uiGates.id" }.count, 2)
        XCTAssertTrue(UIElements.all.contains("notes.documents"), "U17 の要素も同じ一覧にある")
        for k in CrewMemberView.AssignKind.allCases {
            XCTAssertTrue(UIElements.all.contains(UIUnlocks.Element.assign(k.rawValue)), "割り当ての種類と一覧が合う")
        }
    }

    func testGatesCanBeRemovedByLaterLayer() throws {
        var db = try gatedContent()
        try ContentLoader.apply(json: Data(#"{ "remove": { "uiGates": ["tab.base"] } }"#.utf8), to: &db)
        XCTAssertNil(db.uiGates["tab.base"])
        XCTAssertTrue(FrameBuilder(content: db).unlocks(world()).isOpen("tab.base"))
    }

    func testBaseListsStockBuildableAndBuilt() throws {
        let b = FrameBuilder(content: rig.content)
        var w = world()
        let item = try XCTUnwrap(rig.content.structures.values.flatMap(\.cost).compactMap(\.item).first
            ?? Optional<ItemID>("item.test.ui"))
        w.inventory.holders[.base] = [StockEntry(stuff: .item(item), quantity: 3),
                                      StockEntry(stuff: .item(item), quantity: 2)]
        let v = b.base(w)
        XCTAssertEqual(v.stock.map(\.quantity), [5], "同じ名前の山は合わせる")
        XCTAssertFalse(v.stock[0].name.contains("item."), "英語の ID を出さない")
        if let k = rig.content.structures.keys.sorted().first {
            w.research.unlocked.structures.insert(k)
            let opt = try XCTUnwrap(b.base(w).buildable.first { $0.kind == k })
            XCTAssertEqual(opt.cost.count, rig.content.structures[k]?.cost.count)
        }
        XCTAssertTrue(b.base(world()).buildable.allSatisfy { world().research.unlocked.structures.contains($0.kind) })
    }

    func testCrewShowsMembersAndAssignChoicesThatTheHostAccepts() async throws {
        let w = world()
        let host = GameBootstrap.host(content: rig.content, world: w)
        let crew = await host.crew()
        XCTAssertEqual(crew.members.first?.isNoah, true)
        XCTAssertEqual(crew.members.first?.body.health, 1000)
        XCTAssertTrue(crew.choices.contains { $0.kind == .rest })
        XCTAssertTrue(crew.choices.contains { $0.kind == .idle })
        let kinds = crew.choices.map(\.kind)
        let ranks = kinds.map { CrewMemberView.AssignKind.order.firstIndex(of: $0)! }
        XCTAssertEqual(ranks, ranks.sorted(), "種類の順に並ぶ")
        let rest = try XCTUnwrap(crew.choices.first { $0.kind == .rest })
        let (_, rejection) = await host.perform(rest.command(for: .noah))
        XCTAssertNil(rejection)
        let after = await host.crew()
        XCTAssertEqual(after.members.first?.assignment, .rest)
    }

    func testPlacementPreviewShowsWhetherTheSiteIsFree() throws {
        let b = FrameBuilder(content: rig.content)
        let w = world()
        let kind = try XCTUnwrap(rig.content.structures.keys.sorted().first { rig.content.structures[$0]?.placement == nil
            && rig.content.structures[$0]?.requiresBaseArea != false })
        let area = try XCTUnwrap(w.base.area)
        // 拠点の範囲の中で、置ける場所が 1 つはある
        var found: PlacementPreview?
        for y in area.origin.y..<(area.origin.y + area.size.height) {
            for x in area.origin.x..<(area.origin.x + area.size.width) where found == nil {
                let p = b.placementPreview(w, kind: kind, at: GridPoint(x, y))
                if p.placeable { found = p }
            }
        }
        let ok = try XCTUnwrap(found, "拠点の中に置ける場所がある")
        XCTAssertNil(ok.reason)
        XCTAssertTrue(ok.cells.contains(ok.at))
        let out = b.placementPreview(w, kind: kind, at: GridPoint(area.origin.x - 3, area.origin.y - 3))
        XCTAssertFalse(out.placeable, "拠点の外は置けない")
        XCTAssertNotNil(out.reason)
    }

    func testResearchAndBattleDefaults() async throws {
        let w = world()
        let b = FrameBuilder(content: rig.content)
        let r = b.research(w)
        XCTAssertEqual(r.entries.map(\.id), r.entries.map(\.id).sorted())
        for e in r.entries { XCTAssertFalse(e.name.hasPrefix("research."), "英語の ID を出さない") }
        let f = b.build(w, revision: 0, previous: nil, report: nil)
        XCTAssertEqual(f.battles, [])
        XCTAssertEqual(f.defaultStance, w.combat.defaultStance)
        let host = GameBootstrap.host(content: rig.content, world: w)
        let (f2, _) = await host.perform(.combat(.setDefaultStance(stance: .advance)))
        XCTAssertEqual(f2.defaultStance, .advance, "寝ている間の既定の構えが帯に戻る")
    }
}
