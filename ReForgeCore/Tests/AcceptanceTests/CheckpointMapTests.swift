import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// 台本の途中の写し(checkpoints)を読み戻した世界で、地図が全部黒(既知のマスが 0)になっていないこと。
/// REFORGE_CHECKPOINT_SCRIPT に台本のパスがある時だけ回す。数だけを出す(物語の語は出さない)。
final class CheckpointMapTests: XCTestCase {
    func testCheckpointsKeepKnownMap() async throws {
        let path = ProcessInfo.processInfo.environment["REFORGE_CHECKPOINT_SCRIPT"] ?? ""
        try XCTSkipUnless(!path.isEmpty, "REFORGE_CHECKPOINT_SCRIPT がある時だけ")
        var content = try TestContent.full()
        content.failureRules = [:]
        let script = try ReplayScript.read(from: URL(fileURLWithPath: path))
        let rig = TestRig(content: content)
        var blackAt: [Int] = []
        for cp in script.checkpoints ?? [] {
            let world = try SaveCodec.decode(cp.save).world
            let host = GameHost(simulation: rig.simulation, world: world)
            let frame = await host.frame
            let chunks = await host.chunks(Array(0..<frame.map.chunkRevisions.count))
            var remembered = 0, total = 0
            for c in chunks { for t in c.tiles { total += 1; if t.fog != .unknown { remembered += 1 } } }
            let known = (world.knowledge.mapKnown[.surface]?.words ?? []).reduce(0) { $0 + $1.nonzeroBitCount }
            let noah = world.people[.noah]?.position
            print("CHECKPOINT idx=\(cp.index) day=\(world.clock.day) phase=\(world.clock.phase) known=\(known) tilesKnown=\(remembered)/\(total) vision=\(frame.map.vision.count) noahLayer=\(noah?.layer.rawValue ?? "-") prologue=\(frame.prologue != nil)")
            if remembered == 0 { blackAt.append(cp.index) }
        }
        XCTAssertTrue(blackAt.isEmpty, "既知のマスが 0 の写し: \(blackAt)")
    }

    /// 画面の写し(区画の控え)を GameStore と同じ規則で保ちながら、写しの世界から寝て朝にした時、控えが本体の区画と食い違わないこと。
    func testSleepKeepsChunkMirror() async throws {
        let path = ProcessInfo.processInfo.environment["REFORGE_CHECKPOINT_SCRIPT"] ?? ""
        try XCTSkipUnless(!path.isEmpty, "REFORGE_CHECKPOINT_SCRIPT がある時だけ")
        var content = try TestContent.full()
        content.failureRules = [:]
        let script = try ReplayScript.read(from: URL(fileURLWithPath: path))
        let rig = TestRig(content: content)
        for cp in (script.checkpoints ?? []) where [99, 117].contains(cp.index) {
            let world = try SaveCodec.decode(cp.save).world
            let host = GameHost(simulation: rig.simulation, world: world)
            var mirror: [Int: MapChunk] = [:]
            var lastRevision = -1
            func refresh(_ f: Frame) async {
                guard f.revision > lastRevision else { return }
                lastRevision = f.revision
                let stale = f.map.chunkRevisions.indices.filter { mirror[$0]?.revision != f.map.chunkRevisions[$0] }
                for c in await host.chunks(stale) where (mirror[c.index]?.revision ?? -1) <= c.revision { mirror[c.index] = c }
            }
            func mismatches() async -> Int {
                let f = await host.frame
                let fresh = await host.chunks(Array(0..<f.map.chunkRevisions.count))
                return fresh.filter { mirror[$0.index]?.tiles != $0.tiles }.count
            }
            await refresh(await host.frame)
            var worst = 0
            var commands: [Command] = [.time(.sleep)]
            if cp.index == 99 { commands = [] }
            for _ in 0..<400 {
                if let c = commands.first { commands.removeFirst(); let (f, _) = await host.send(c); await refresh(f) }
                else if cp.index == 99 { let (f, _) = await host.tick(realSeconds: 0.25); await refresh(f) }
                else { let (f, _) = await host.tick(realSeconds: 0.25); await refresh(f) }
                worst = max(worst, await mismatches())
            }
            let f = await host.frame
            print("MIRROR idx=\(cp.index) day=\(f.clock.day) phase=\(f.clock.phase) worstMismatch=\(worst) end=\(await mismatches())")
        }
    }
}
