import Foundation
import RFKernel
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class SaveBookTests: XCTestCase {
    func dayWorld(_ base: WorldState, day: Int) -> WorldState {
        var w = base
        w.clock.day = day
        w.clock.now = GameTime(seconds: Int64(day - 1) * 26 * 3600)
        return w
    }

    /// 夜明けの自動セーブは同じ走行の直近 3 日を残す。失敗した世界は書かない。別の走行の夜明けは消す。
    func testDawnAutosaveKeepsLatestThree() throws {
        let rig = try TestRig.publicOnly()
        let book = SaveBook(storage: MemorySaveStorage(), content: Fixture.stamp)
        let other = rig.factory.newWorld(seed: 99)
        try book.autosaveDawn(other)
        let w = rig.factory.newWorld(seed: 1)
        for d in 1...5 { try book.autosaveDawn(dayWorld(w, day: d)) }
        XCTAssertEqual(try book.savePoints().map(\.slot), [.dawn(day: 5), .dawn(day: 4), .dawn(day: 3)])
        var failed = dayWorld(w, day: 6)
        failed.run.outcome = .failed(cause: "text.test.cause", record: nil)
        XCTAssertFalse(try book.autosaveDawn(failed))
        XCTAssertEqual(try book.rewindTargets(for: dayWorld(w, day: 4)).map(\.slot), [.dawn(day: 4), .dawn(day: 3)])
    }

    /// 手動は 3 枠。一覧は夜明けの新しい順 → 手動の番号順。読めない保存は理由つきで一覧に残す(黙って落とさない)。
    func testManualSlotsAndListing() throws {
        let rig = try TestRig.publicOnly()
        let storage = MemorySaveStorage()
        let book = SaveBook(storage: storage, content: Fixture.stamp)
        let w = rig.factory.newWorld(seed: 1)
        try book.saveManual(w, index: 2)
        try book.saveManual(w, index: 0)
        XCTAssertThrowsError(try book.saveManual(w, index: 3)) {
            XCTAssertEqual($0 as? SaveBookError, .noSuchManualSlot(3))
        }
        try book.autosaveDawn(w)
        try storage.write(Data("broken".utf8), slot: .manual(index: 1))
        try book.writeResume(w, screen: Data(#"{"mode":"place"}"#.utf8))
        let points = try book.savePoints()
        XCTAssertEqual(points.map(\.slot), [.dawn(day: 1), .manual(index: 0), .manual(index: 1), .manual(index: 2)])
        XCTAssertNil(points[2].summary)
        XCTAssertNotNil(points[2].problem)
        XCTAssertEqual(points[1].summary?.run, 1)
    }

    /// 最初から: 前の走行の夜明け・続き・画面の状態を消し、手動は残す。時間軸を切り替える: 先の夜明けを消す。
    func testStartNewAndAdoptTimeline() throws {
        let rig = try TestRig.publicOnly()
        let book = SaveBook(storage: MemorySaveStorage(), content: Fixture.stamp)
        let w = rig.factory.newWorld(seed: 1)
        for d in 1...3 { try book.autosaveDawn(dayWorld(w, day: d)) }
        try book.saveManual(dayWorld(w, day: 2), index: 0)
        try book.writeResume(w, screen: Data("{}".utf8))
        try book.adoptTimeline(dayWorld(w, day: 2))
        XCTAssertEqual(try book.savePoints().map(\.slot), [.dawn(day: 2), .dawn(day: 1), .manual(index: 0)])
        let fresh = rig.factory.newWorld(seed: 5)
        try book.startNew(fresh)
        XCTAssertEqual(try book.savePoints().map(\.slot), [.dawn(day: 1), .manual(index: 0)])
        XCTAssertEqual(try book.load(.dawn(day: 1))?.summary.seed, 5)
        XCTAssertEqual(try book.readResume()?.world, fresh)
        XCTAssertNil(try book.readScreen())
    }

    /// ファイルの置き場(アプリが使う)。名前から場所が戻り、上書き・消すができる。
    func testFileStorage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rfsave-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rig = try TestRig.publicOnly()
        let book = SaveBook(storage: FileSaveStorage(directory: dir), content: Fixture.stamp)
        let w = Fixture.world(rig)
        try book.writeResume(w, screen: Data("{\"x\":1}".utf8))
        try book.autosaveDawn(w)
        try book.saveManual(w, index: 1)
        XCTAssertEqual(Set(try book.storage.list()), [.resume, .screen, .dawn(day: 1), .manual(index: 1)])
        XCTAssertEqual(try book.readResume()?.world, w)
        XCTAssertEqual(try book.readScreen(), Data("{\"x\":1}".utf8))
        try book.storage.delete(slot: .manual(index: 1))
        XCTAssertNil(try book.load(.manual(index: 1)))
    }

    /// TEST-R1-08(本体側): 昼の途中(実時間の端数あり)・歩いている途中・会話の場面の途中・決断待ち・置くモード(画面側)で
    /// 続きを書き、読んで戻すと、その場から続く。閉じていた間は進まない(本体は壁時計を読まない)ので、
    /// 読んだ世界は書いた世界と同じで、同じ実時間を進めた結果も、閉じなかった場合と同じ。
    func testResumeContinuesFromTheSameMoment() throws {
        let rig = try TestRig.publicOnly()
        var w = Fixture.world(rig)
        _ = rig.simulation.advance(&w, realSeconds: 0.37)
        _ = rig.simulation.advance(&w, realSeconds: 0.81)
        XCTAssertNotEqual(w.clock.realCarry, 0, "実時間の端数がある時点で閉じる")
        let spawn = w.people[.noah]!.position!
        w.people[.noah]?.motion = Motion(path: [GridPoint(spawn.point.x + 1, spawn.point.y),
                                                GridPoint(spawn.point.x + 2, spawn.point.y)], progress: 400)
        w.people[.noah]?.activity = .walking(to: WorldPoint(spawn.layer, GridPoint(spawn.point.x + 2, spawn.point.y)))
        w.narrative.scene = SceneProgress(scene: "scene.test.one", line: 1)
        w.narrative.pending = [PendingDecision(id: w.newEntityID(), event: "event.test.decision",
                                               choices: ["choice.test.yes", "choice.test.no"], blocking: false,
                                               since: w.clock.now, origin: nil)]
        let screen = Data(#"{"placing":{"module":"furnace","at":[3,4],"facing":"east"},"draft":["crush","smelt"]}"#.utf8)

        let book = SaveBook(storage: MemorySaveStorage(), content: Fixture.stamp)
        try book.writeResume(w, screen: screen)
        let restored = try XCTUnwrap(book.readResume())
        XCTAssertEqual(restored.world, w)
        XCTAssertEqual(restored.slot, .resume)
        XCTAssertEqual(try book.readScreen(), screen)

        var a = w
        var b = restored.world
        let ra = rig.simulation.advance(&a, realSeconds: 1.0)
        let rb = rig.simulation.advance(&b, realSeconds: 1.0)
        XCTAssertGreaterThan(ra.steps, 0)
        XCTAssertEqual(ra.steps, rb.steps)
        XCTAssertEqual(ra.events, rb.events)
        XCTAssertEqual(a, b)
    }

    /// 1 日遊んで寝た世界も、書いて読んで同じ(全部の切れ端が往復で変わらない)。
    func testPlayedWorldRoundTrips() throws {
        let rig = try TestRig.publicOnly()
        var w = Fixture.world(rig)
        _ = rig.playDay(&w)
        _ = rig.simulation.apply(.time(.sleep), to: &w)
        let book = SaveBook(storage: MemorySaveStorage(), content: Fixture.stamp)
        try book.autosaveDawn(w)
        XCTAssertEqual(try book.load(.dawn(day: w.clock.day))?.world, w)
    }
}
