import Foundation
import RFKernel
import RFPresent
import RFSave
import RFContent
import RFRules
import RFSim
import RFWorld
import RFTestSupport
import XCTest

final class LanguageSwitchTests: XCTestCase {
    private func save(_ host: GameHost) async throws -> Data {
        try await host.saveData(slot: .resume, stamps: [])
    }

    /// 同じ命令列(歩く・行為・夜は寝る・時間の経過)を 3 つの host に送る。基準(ja のまま)・途中で何度も切り替える・pseudo のまま。
    /// 毎歩、保存が一致し、世界の時計が実際に進むこと。
    func testLanguageDoesNotChangeTwoHundredStepsOfWorld() async throws {
        let rig = try TestRig.publicOnly()
        let world = rig.factory.newWorld(seed: 71)
        let base = GameHost(simulation: rig.simulation, world: world, language: .ja)
        let switching = GameHost(simulation: rig.simulation, world: world, language: .ja)
        let pseudo = GameHost(simulation: rig.simulation, world: world, language: .pseudo)
        let hosts = [base, switching, pseudo]
        let size = world.map[.surface]!.size
        let start = world.clock.now

        for i in 0..<200 {
            if i % 7 == 3 { _ = await switching.setLanguage(i % 14 == 3 ? .pseudo : .ja) }
            var command: Command?
            let phase = await base.world.clock.phase
            if phase != .day {
                command = .time(.sleep)
            } else if i % 25 == 0 {
                let p = GridPoint((i * 7 + 3) % size.width, (i * 5 + 2) % size.height)
                command = .crew(.walk(to: WorldPoint(.surface, p)))
            } else if i % 25 == 12 {
                let at = await base.world.map.spawn
                if let act = await base.footCard(at: at.point)?.actions.first {
                    command = .exploration(.interact(interaction: act.id, at: at, holding: false))
                }
            }
            var frames: [Frame] = []
            for host in hosts {
                if let command { _ = await host.send(command) }
                frames.append(await host.tick(realSeconds: 0.5).frame)
            }
            let saves = try await hosts.asyncMap { try await self.save($0) }
            XCTAssertEqual(saves[0], saves[1], "step \(i): 途中で切り替えた host")
            XCTAssertEqual(saves[0], saves[2], "step \(i): pseudo host")
            XCTAssertEqual(frames[0].darkStart?.action.id, frames[2].darkStart?.action.id)
            XCTAssertEqual(frames[0].clock, frames[1].clock)
            let point = frames[0].focus ?? world.map.spawn.point
            let ja = await base.footCard(at: point)?.actions.map(\.id)
            let ps = await pseudo.footCard(at: point)?.actions.map(\.id)
            XCTAssertEqual(ja, ps)
        }
        let end = await base.world.clock.now
        XCTAssertGreaterThan(end.seconds, start.seconds, "世界の時計が進んでいる")
        let replayed = await base.replayLog.count
        XCTAssertGreaterThan(replayed, 5)
    }

    /// 序・決断・断りがある世界の途中(地図の途中・序の最中・決断の最中・断りの後)で切り替える。
    func testSwitchInPrologueDecisionRejectionAndMapKeepsStructure() async throws {
        var content = try TestContent.publicOnly()
        content.texts["text.test.prologue.first"] = "試験の一行目"
        content.texts["text.test.prologue.second"] = "試験の二行目"
        try ContentLoader.apply(json: Data(#"""
        {
          "scenes": [
            { "id": "scene.test.prologue.1", "style": "prologue", "then": "scene.test.prologue.2",
              "lines": [ { "text": "text.test.prologue.first" } ] },
            { "id": "scene.test.prologue.2", "style": "prologue",
              "lines": [ { "text": "text.test.prologue.second" } ] }
          ],
          "events": [
            { "id": "event.test.prologue", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.prologue.1" }
          ],
          "interactions": [
            { "id": "interaction.test.prologue", "target": { "terrain": { "tag": "ground" } },
              "seconds": 1, "hold": false, "yields": [] }
          ]
        }
        """#.utf8), to: &content)
        content.start.events = ["event.test.prologue"]
        content.start.clock = StartClockDef(held: true, firstAct: "interaction.test.prologue")
        let rig = TestRig(content: content)
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 9))
        let jaValues = rig.content.textTables.tables[.ja].map { Set($0.values.filter { $0.count > 2 }) } ?? []

        func checkSwitch(_ label: String) async throws {
            let before = await host.frame
            let saved = try await save(host)
            let pseudo = await host.setLanguage(.pseudo)
            // 表の文は全部包まれ、素の表の文は 1 つも残らない
            let strings = FrameText.allStrings(pseudo)
            XCTAssertFalse(strings.contains { jaValues.contains($0) }, "\(label): 素の文が残っている")
            XCTAssertTrue(strings.contains { $0.hasPrefix("⟦") } || FrameText.allStrings(before).allSatisfy { !jaValues.contains($0) }, label)
            XCTAssertEqual(pseudo.prologue?.lines.count, before.prologue?.lines.count, label)
            XCTAssertEqual(pseudo.prologue?.waiting, before.prologue?.waiting, label)
            XCTAssertEqual(pseudo.sceneLines.count, before.sceneLines.count, label)
            XCTAssertEqual(pseudo.decision?.choices.map(\.id), before.decision?.choices.map(\.id), label)
            let pseudoSave = try await save(host)
            XCTAssertEqual(pseudoSave, saved, label)
            var restored = await host.setLanguage(.ja)
            XCTAssertGreaterThan(restored.revision, pseudo.revision)
            // 版(Frame と区画)だけが進み、それ以外は元と同じ
            restored.revision = before.revision
            restored.map.chunkRevisions = before.map.chunkRevisions
            restored.benchRevision = before.benchRevision
            XCTAssertEqual(restored, before, label)
            let restoredSave = try await save(host)
            XCTAssertEqual(restoredSave, saved, label)
        }

        // 序の最中
        try await checkSwitch("序 1 ページ目")
        _ = await host.send(.narrative(.advanceScene))
        try await checkSwitch("序 2 ページ目")
        _ = await host.send(.narrative(.advanceScene))
        _ = await host.send(.narrative(.advanceScene))
        // 断りがある間(夜でない昼に寝る)
        let (_, report) = await host.send(.time(.sleep))
        XCTAssertNotNil(report.rejection)
        let kept = await host.lastRejection
        XCTAssertNotNil(kept)
        try await checkSwitch("断りがある")
        let afterRef = await host.lastRejection
        XCTAssertEqual(afterRef, kept)
        // 受け付けられた操作は断りを消す
        let at = await host.world.map.spawn
        let card = await host.footCard(at: at.point)
        let act = try XCTUnwrap(card?.actions.first)
        _ = await host.send(.exploration(.interact(interaction: act.id, at: at, holding: false)))
        let cleared = await host.lastRejection
        XCTAssertNil(cleared)
        // 地図の途中
        for i in 0..<40 { _ = await host.tick(realSeconds: 0.5); _ = i }
        try await checkSwitch("地図の途中")
    }

    /// 決断が出ている間に切り替える。
    func testSwitchDuringDecision() async throws {
        let content = try TestContent.publicOnly()
        let rig = TestRig(content: content)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: content)
        ctx.learn("fact.test.alpha")
        var report = StepReport()
        rig.simulation.settle(&ctx, &report)
        let host = GameHost(simulation: rig.simulation, world: ctx.world)
        let before = await host.frame
        XCTAssertNotNil(before.decision)
        let jaValues = Set((content.textTables.tables[.ja] ?? [:]).values.filter { $0.count > 2 })
        let pseudo = await host.setLanguage(.pseudo)
        XCTAssertEqual(pseudo.decision?.choices.map(\.id), before.decision?.choices.map(\.id))
        XCTAssertFalse(FrameText.allStrings(pseudo).contains { jaValues.contains($0) })
        XCTAssertTrue(pseudo.decision?.choices.allSatisfy { $0.label.hasPrefix("⟦") } ?? false)
        let back = await host.setLanguage(.ja)
        XCTAssertEqual(back.decision, before.decision)
    }

    /// GameHost.replace(world:) は前の世界の断りを持ち越さない。
    func testReplaceWorldClearsRejection() async throws {
        let rig = try TestRig.publicOnly()
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 5))
        _ = await host.send(.time(.sleep))
        let stored = await host.lastRejection
        XCTAssertNotNil(stored)
        _ = await host.replace(world: rig.factory.newWorld(seed: 6))
        let cleared = await host.lastRejection
        XCTAssertNil(cleared)
    }

    /// 言語の切り替えは世界を変えず、現在の Frame を丸ごと組み直す。
    func testSwitchRebuildsFrameWithoutChangingWorld() async throws {
        let rig = try TestRig.publicOnly()
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 3))
        let before = await host.frame
        let saved = try await save(host)

        let pseudo = await host.setLanguage(.pseudo)
        let pseudoSave = try await save(host)
        XCTAssertEqual(pseudoSave, saved)
        XCTAssertGreaterThan(pseudo.revision, before.revision)
        XCTAssertFalse(pseudo.status.isEmpty)
        XCTAssertTrue(pseudo.status.map(\.label).allSatisfy { $0.hasPrefix("⟦") })
        XCTAssertEqual(pseudo.sceneLines.count, before.sceneLines.count)
        XCTAssertEqual(pseudo.prologue?.lines.count, before.prologue?.lines.count)
        XCTAssertEqual(pseudo.decision?.choices.map(\.id), before.decision?.choices.map(\.id))

        let restored = await host.setLanguage(.ja)
        let restoredSave = try await save(host)
        XCTAssertEqual(restoredSave, saved)
        XCTAssertEqual(FrameText.allStrings(restored), FrameText.allStrings(before))
    }

    /// 断りは組んだ文字列でなく TextRef として残り、現在の言語で組み直せる。
    func testRejectionReferenceRendersAfterLanguageSwitch() async throws {
        let rig = try TestRig.publicOnly()
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 5))
        let (_, report) = await host.send(.time(.sleep))
        let rejection = try XCTUnwrap(report.rejection)
        let expected = await host.rejectionRef(rejection)
        let before = await host.lastRejection
        XCTAssertEqual(before, expected)

        _ = await host.setLanguage(.pseudo)
        let rendered = await host.describe(rejection)
        let after = await host.lastRejection
        XCTAssertTrue(rendered.hasPrefix("⟦"))
        XCTAssertEqual(after, expected)
    }

    /// 保存の JSON に、出荷する言語の表の文そのものを持ち込まない。
    func testSaveContainsNoTextTableValues() async throws {
        let rig = try TestRig.publicOnly()
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 13))
        for _ in 0..<200 { _ = await host.tick(realSeconds: 0.1) }
        let data = try await save(host)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data))
        let tableValues = LanguageID.released.compactMap { rig.content.textTables.tables[$0] }
            .reduce(into: Set<String>()) { $0.formUnion($1.values) }
        XCTAssertTrue(Set(stringValues(in: object)).isDisjoint(with: tableValues))
    }

    /// 言語で地図の字も替わるので、全区画を新しい版にする。
    func testSwitchAdvancesEveryMapChunkRevision() async throws {
        let rig = try TestRig.publicOnly()
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 19))
        let before = await host.frame
        let saved = try await save(host)
        let changed = await host.setLanguage(.pseudo)
        XCTAssertTrue(zip(before.map.chunkRevisions, changed.map.chunkRevisions).allSatisfy { $1 > $0 })
        let again = await host.setLanguage(.pseudo)
        let afterSave = try await save(host)
        let currentWorld = await host.world
        XCTAssertEqual(afterSave, saved)
        XCTAssertEqual(currentWorld, rig.factory.newWorld(seed: 19))
        XCTAssertTrue(zip(changed.map.chunkRevisions, again.map.chunkRevisions).allSatisfy { $1 >= $0 })
    }

    private func stringValues(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let values = value as? [Any] { return values.flatMap { stringValues(in: $0) } }
        if let values = value as? [String: Any] { return values.values.flatMap { stringValues(in: $0) } }
        return []
    }
}

private extension Array {
    func asyncMap<T>(_ f: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await f(e)) }
        return out
    }
}
