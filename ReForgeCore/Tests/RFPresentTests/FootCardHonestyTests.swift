import Foundation
import RFContent
import RFExploration
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 足元カードは嘘をつかない(B・F)。
/// - 使い切りのマスの足元カードに、周りの未使用のマスの行為が「題のマスの行為」に見える形で出ない。
/// - カードの全ページの全行為は、そのまま送れば断られない。
final class FootCardHonestyTests: XCTestCase {
    var rig: TestRig!
    var builder: FrameBuilder!
    let pick: InteractionID = "interaction.pick_sticks"

    override func setUpWithError() throws {
        rig = try TestRig.publicOnly()
        builder = FrameBuilder(content: rig.content)
    }

    // MARK: 道具

    /// ノアが noah に立ち、forest の各マスが森の世界(周りの 8 マスのうち森にしない所は地面にする)。
    func world(noahAt noah: GridPoint? = nil, forest: [GridPoint], around: Bool = true) -> (w: WorldState, noah: GridPoint) {
        var w = rig.factory.newWorld(seed: 1)
        let here = noah ?? (w.map.spawn.point + GridPoint(3, 0))
        if around {
            for dy in -2...2 { for dx in -2...2 { w.map[.surface]?.setTerrain("grass", at: here + GridPoint(dx, dy)) } }
        }
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        for dy in -3...3 { for dx in -3...3 { bits[here + GridPoint(dx, dy)] = true } }
        for q in forest { w.map[.surface]?.setTerrain("forest", at: q) }
        w.knowledge.mapKnown[.surface] = bits
        w.people[.noah]?.position = WorldPoint(.surface, here)
        w.people[.noah]?.motion = nil
        return (w, here)
    }

    func pickNow(_ w: inout WorldState, at cell: GridPoint) {
        let r = rig.simulation.apply(.exploration(.interact(interaction: pick, at: WorldPoint(.surface, cell), holding: true)), to: &w)
        XCTAssertNil(r.rejection)
        var n = 0
        while w.exploration.active[.noah] != nil && n < 2000 {
            _ = rig.simulation.runSteps(1, &w)
            n += 1
        }
    }

    func allActions(_ w: WorldState, at pt: GridPoint) -> [FootCard.Action] {
        guard let first = builder.footCard(w, at: pt) else { return [] }
        var out = first.actions
        for page in stride(from: 1, to: first.pageCount, by: 1) {
            out += builder.footCard(w, at: pt, page: page)?.actions ?? []
        }
        return out
    }

    /// ノアの周り(5×5)のマスの足元カードの全ページの全行為を、そのまま送って断られないことを確かめる。数を返す。
    @discardableResult
    func assertEveryCardActionIsAccepted(_ w: WorldState, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let noah = w.people[.noah]?.position?.point else { return 0 }
        var sent = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let pt = noah + GridPoint(dx, dy)
                for a in allActions(w, at: pt) {
                    var copy = w
                    let r = rig.simulation.apply(a.start, to: &copy)
                    sent += 1
                    XCTAssertNil(r.rejection, "\(label): \(pt) のカードの \(a.id.rawValue) が断られた(\(r.rejection?.reason.rawValue ?? ""))",
                                 file: file, line: line)
                }
            }
        }
        return sent
    }

    // MARK: B

    /// 使い切りの林に立つと、周りに未使用の森があっても、その林のカードに「拾う」は出ない。
    func testSpentTileCardShowsNoPickEvenWhenNeighbourIsFresh() throws {
        let here = rig.factory.newWorld(seed: 1).map.spawn.point + GridPoint(3, 0)
        let fresh = here + GridPoint(1, 0)
        var (w, noah) = world(noahAt: here, forest: [here, fresh])
        XCTAssertEqual(noah, here)
        XCTAssertNotNil(allActions(w, at: here).first { $0.id == pick }, "使う前は出る")
        pickNow(&w, at: here)
        XCTAssertEqual(builder.tile(w, at: here).glyph, TilePalette.spentGlyph)
        XCTAssertNil(allActions(w, at: here).first { $0.id == pick }, "使い切りの林のカードに、隣の林の行為を出さない")
        // 隣の未使用の林のカードでは、その林に向けて出て、押せば通る
        let a = try XCTUnwrap(allActions(w, at: fresh).first { $0.id == pick })
        XCTAssertEqual(a.at.point, fresh)
        var copy = w
        XCTAssertNil(rig.simulation.apply(a.start, to: &copy).rejection)
    }

    func testSpentTileCardShowsNoPickWhenNothingIsFreshAround() throws {
        let here = rig.factory.newWorld(seed: 1).map.spawn.point + GridPoint(3, 0)
        var (w, _) = world(noahAt: here, forest: [here])
        pickNow(&w, at: here)
        XCTAssertNil(allActions(w, at: here).first { $0.id == pick })
        XCTAssertTrue(builder.footCard(w, at: here)?.actions.isEmpty ?? false)
    }

    /// 地面に立って周りの未使用の森を拾う行為が出るなら、それは実際にその森へ向き、押して通る。
    func testGroundCardActionTargetsAFreshNeighbourAndIsAccepted() throws {
        let here = rig.factory.newWorld(seed: 1).map.spawn.point + GridPoint(3, 0)
        let spent = here + GridPoint(1, 0), fresh = here + GridPoint(0, 1)
        var (w, _) = world(noahAt: here, forest: [spent, fresh])
        pickNow(&w, at: spent)
        let a = try XCTUnwrap(allActions(w, at: here).first { $0.id == pick })
        XCTAssertEqual(a.at.point, fresh, "使い切りの林ではなく、未使用の林へ向く")
        var copy = w
        XCTAssertNil(rig.simulation.apply(a.start, to: &copy).rejection)
        assertEveryCardActionIsAccepted(w, "地面の周りに使い切りと未使用")
    }

    // MARK: F

    func testEveryCardActionIsAcceptedInPublicWorlds() throws {
        let spawn = rig.factory.newWorld(seed: 1).map.spawn.point
        var total = 0

        // 初期の世界(ノアは出発点)
        var w0 = rig.factory.newWorld(seed: 1)
        w0.clock.held = false
        total += assertEveryCardActionIsAccepted(w0, "初期")

        // 森(使う前・使った後)
        let here = spawn + GridPoint(3, 0)
        var (wf, _) = world(noahAt: here, forest: [here, here + GridPoint(1, 0), here + GridPoint(-1, 1), here + GridPoint(0, -1)])
        wf.clock.held = false
        XCTAssertGreaterThan(assertEveryCardActionIsAccepted(wf, "森"), 0, "試験が空振りでない")
        pickNow(&wf, at: here)
        total += assertEveryCardActionIsAccepted(wf, "森(1 回採った後)")
        pickNow(&wf, at: here + GridPoint(1, 0))
        total += assertEveryCardActionIsAccepted(wf, "森(2 マス使い切り)")

        // 夜(夜作業・日没)
        var wn = wf
        var n = 0
        while wn.clock.phase == .day && n < 100_000 { _ = rig.simulation.runSteps(100, &wn); n += 1 }
        total += assertEveryCardActionIsAccepted(wn, "日没以降(\(wn.clock.phase))")
        XCTAssertEqual(wn.clock.phase, .dusk)
        XCTAssertEqual(rig.simulation.apply(.time(.startNightWork), to: &wn).rejection?.reason, nil)
        XCTAssertEqual(wn.clock.phase, .nightWork)
        total += assertEveryCardActionIsAccepted(wn, "夜作業")

        // 時計の保留(始まりの暗い画面)・終わった走り: 行為のボタンを出さないか、出すなら通る
        var wh = wf
        wh.clock.held = true
        total += assertEveryCardActionIsAccepted(wh, "時計の保留")
        var wd = wf
        wd.run.outcome = .failed(cause: "text.unknown", record: nil)
        total += assertEveryCardActionIsAccepted(wd, "走りが終わった後")

        // 水
        var (ww, wHere) = world(noahAt: here, forest: [])
        ww.clock.held = false
        ww.map[.surface]?.setTerrain("shore", at: wHere + GridPoint(1, 1))
        XCTAssertGreaterThan(assertEveryCardActionIsAccepted(ww, "水"), 0)
        XCTAssertGreaterThan(total, 0, "試験が空振りでない")
    }
}
