import Foundation
import RFKernel
import RFPresent
import RFSave
import RFSim
import RFTestSupport
import XCTest

final class LanguageSwitchTests: XCTestCase {
    private func save(_ host: GameHost) async throws -> Data {
        try await host.saveData(slot: .resume, stamps: [])
    }

    /// 言語は世界・乱数・保存に入らない。同じ歩みなら保存と行為の ID は同じ。
    func testLanguageDoesNotChangeTwoHundredStepsOfWorld() async throws {
        let rig = try TestRig.publicOnly()
        let world = rig.factory.newWorld(seed: 71)
        let japanese = GameHost(simulation: rig.simulation, world: world, language: .ja)
        let pseudo = GameHost(simulation: rig.simulation, world: world, language: .pseudo)

        for _ in 0..<200 {
            let (jaFrame, _) = await japanese.tick(realSeconds: 0.1)
            let (pseudoFrame, _) = await pseudo.tick(realSeconds: 0.1)
            let jaSave = try await save(japanese)
            let pseudoSave = try await save(pseudo)
            XCTAssertEqual(jaSave, pseudoSave)
            XCTAssertEqual(jaFrame.darkStart?.action.id, pseudoFrame.darkStart?.action.id)
            let point = jaFrame.focus ?? world.map.spawn.point
            let jaActions = await japanese.footCard(at: point)?.actions.map(\.id)
            let pseudoActions = await pseudo.footCard(at: point)?.actions.map(\.id)
            XCTAssertEqual(jaActions, pseudoActions)
        }
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
