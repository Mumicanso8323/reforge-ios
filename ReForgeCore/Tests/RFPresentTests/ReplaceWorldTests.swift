import Foundation
import RFKernel
import RFPresent
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 保存を読み戻して世界を差し替える(つづきから・巻き戻し・台本の合わせ直し)と、画面の材料が保存前と同じになること。
/// 地図の視界・区画の版と指紋・区画の中身・足元カード・置いた物が、差し替えで欠けたり古いまま残ったりしない。
final class ReplaceWorldTests: XCTestCase {
    var rig: TestRig!

    override func setUpWithError() throws { rig = try TestRig.publicOnly() }

    private func roundTrip(_ w: WorldState) throws -> WorldState {
        let env = SaveEnvelope(slot: .resume, world: w, content: [])
        return try SaveCodec.decode(try SaveCodec.encode(env)).world
    }

    private func knownCount(_ w: WorldState) -> Int {
        (w.knowledge.mapKnown[.surface]?.words ?? []).reduce(0) { $0 + $1.nonzeroBitCount }
    }

    /// 世界を進める: 昼の間歩いて視界を広げ、夜を越えて 2 日目の朝にする。節目ごとの世界を返す。
    private func stages() -> [(String, WorldState)] {
        var w = rig.factory.newWorld(seed: 7)
        var out: [(String, WorldState)] = [("初日の朝", w)]
        let size = w.map[.surface]!.size
        var target = 0
        var n = 0
        while w.clock.phase == .day, n < 100_000 {
            if n % 150 == 0 {
                target += 1
                let p = GridPoint((target * 7) % size.width, (target * 5) % size.height)
                _ = rig.simulation.apply(.crew(.walk(to: WorldPoint(.surface, p))), to: &w)
            }
            _ = rig.simulation.advance(&w, realSeconds: 0.1)
            n += 1
            if n == 600 { out.append(("初日の昼(歩いた後)", w)) }
        }
        out.append(("初日の日没", w))
        _ = rig.simulation.apply(.time(.sleep), to: &w)
        out.append(("2 日目の朝", w))
        return out
    }

    private func assertSameScreen(_ a: Frame, _ b: Frame, ahead: GameHost, behind: GameHost, _ label: String,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertEqual(a.map.vision, b.map.vision, "\(label): 視界", file: file, line: line)
        XCTAssertEqual(a.map.chunkSignatures, b.map.chunkSignatures, "\(label): 区画の指紋", file: file, line: line)
        XCTAssertEqual(a.placements, b.placements, "\(label): 置いた物", file: file, line: line)
        XCTAssertEqual(a.actors, b.actors, "\(label): 人", file: file, line: line)
        XCTAssertEqual(a.map.beacons, b.map.beacons, "\(label): 目印", file: file, line: line)
        XCTAssertEqual(a.clock, b.clock, "\(label): 時計", file: file, line: line)
        let all = Array(0..<a.map.chunkRevisions.count)
        let ca = await ahead.chunks(all), cb = await behind.chunks(all)
        XCTAssertEqual(ca.map(\.tiles), cb.map(\.tiles), "\(label): 区画の中身", file: file, line: line)
    }

    /// 保存して読み戻した世界は、保存前の世界と同じ画面の材料を作る。
    func testRoundTripBuildsSameFrame() throws {
        let builder = FrameBuilder(content: rig.content)
        let all = stages()
        for (label, w) in all {
            let back = try roundTrip(w)
            XCTAssertEqual(back, w, "\(label): 世界")
            XCTAssertEqual(back.knowledge.mapKnown, w.knowledge.mapKnown, "\(label): 地図の既知")
            let a = builder.build(w, revision: 5, previous: nil, report: nil)
            let b = builder.build(back, revision: 5, previous: nil, report: nil)
            XCTAssertEqual(a, b, label)
        }
        let before = knownCount(all[0].1), after = knownCount(all.last!.1)
        XCTAssertGreaterThan(after, before, "視界を広げた(\(before) → \(after))")
    }

    /// 進んだ host に別の世界を差し替えると、版が進み、全区画が新しい版になり、区画の中身が差し替えた世界のものになる。
    func testReplaceOnUsedHostMatchesFreshHost() async throws {
        let all = stages()
        let host = GameHost(simulation: rig.simulation, world: all[0].1)
        for _ in 0..<5 { _ = await host.tick(realSeconds: 0.5) }
        for (label, w) in all {
            let back = try roundTrip(w)
            let old = await host.frame
            let f = await host.replace(world: back)
            XCTAssertGreaterThan(f.revision, old.revision, label)
            XCTAssertEqual(f.map.chunkRevisions, Array(repeating: f.revision, count: f.map.chunkRevisions.count),
                           "\(label): 差し替えたら全区画が新しい版(画面の写しが古いまま残らない)")
            let fresh = GameHost(simulation: rig.simulation, world: back)
            let g = await fresh.frame
            await assertSameScreen(f, g, ahead: host, behind: fresh, label)
            for pt in [f.focus ?? GridPoint(2, 2), GridPoint(30, 30)] {
                let c1 = await host.footCard(at: pt), c2 = await fresh.footCard(at: pt)
                XCTAssertEqual(c1, c2, "\(label): 足元カード \(pt)")
            }
        }
    }

    /// 差し替えの後に歩みを進めても、版は単調に進み、区画の版が差し替えの版より戻らない。
    func testStepsAfterReplaceKeepRevisionsMonotonic() async throws {
        let all = stages()
        let host = GameHost(simulation: rig.simulation, world: all[0].1)
        for _ in 0..<5 { _ = await host.tick(realSeconds: 0.5) }
        let f = await host.replace(world: try roundTrip(all.last!.1))
        let (g, _) = await host.tick(realSeconds: 0.5)
        XCTAssertGreaterThan(g.revision, f.revision)
        for (a, b) in zip(f.map.chunkRevisions, g.map.chunkRevisions) { XCTAssertGreaterThanOrEqual(b, a) }
    }
}
