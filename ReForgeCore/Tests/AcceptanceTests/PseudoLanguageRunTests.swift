import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// 公開の短い通しを、表にない文を強調する擬似言語でも走らせる。
final class PseudoLanguageRunTests: XCTestCase {
    private func save(_ host: GameHost) async throws -> Data {
        try await host.saveData(slot: .resume, stamps: [])
    }

    private func inspect(_ frame: Frame, content: ContentDB, known: Set<FactID>, language: LanguageID,
                         auditor: PerceptionAuditor, step: Int) {
        let strings = FrameText.allStrings(frame)
        // Frame は画面に渡さない内部 ID も持つ。Perceiver が監査する表示文だけを、ID の規則そのもので分ける。
        let displayed = strings.filter {
            !ForbiddenAudit.looksLikeInternalID($0, allowed: content.latinAllowedByLanguage[language], language: language)
        }
        for text in displayed {
            auditor.inspect(text, content: content, known: known, origin: "pseudo-run.\(step)", language: language)
        }
        if language == .pseudo {
            XCTAssertEqual(PseudoCheck.unwrapped(strings), [], "pseudo frame \(step) has unwrapped localized text")
        }
    }

    /// 30 分ぶん進め、毎歩の Frame を擬似言語で確かめる。言語を途中で替えても保存は変わらない。
    func testPublicRunUsesOnlyWrappedPseudoTextAndPreservesWorld() async throws {
        let rig = try TestRig.publicOnly()
        let world = rig.factory.newWorld(seed: 83)
        let languages = TestText.languages(for: rig.content)
        let runs = languages.map { (language: $0, host: GameHost(simulation: rig.simulation, world: world, language: $0),
                                    auditor: PerceptionAuditor(stage: "pseudo-run")) }
        let base = try XCTUnwrap(runs.first { $0.language == .ja })
        let switching = GameHost(simulation: rig.simulation, world: world, language: .ja)

        let staticAudits = ForbiddenAudit.auditAll(rig.content)
        XCTAssertTrue(staticAudits.values.allSatisfy(\.isEmpty), "static perception audit has violations")

        func inspectRuns(_ step: Int) async {
            for run in runs {
                inspect(await run.host.frame, content: rig.content, known: await run.host.world.knowledge.factSet,
                        language: run.language, auditor: run.auditor, step: step)
            }
        }

        await inspectRuns(-1)
        var beganDarkStart = false
        for step in 0..<450 { // 0.5 秒ずつ、昼の倍率では 30 分以上のゲーム内時間
            let baseFrame = await base.host.frame
            var command: Command?
            if !beganDarkStart, let action = baseFrame.darkStart?.action {
                command = action.start
                beganDarkStart = true
            } else if baseFrame.clock.phase != .day {
                command = .time(.sleep)
            } else if step % 90 == 20 {
                let size = (await base.host.world).map[.surface]!.size
                let point = GridPoint((step * 7 + 3) % size.width, (step * 5 + 1) % size.height)
                command = .crew(.walk(to: WorldPoint(.surface, point)))
            } else if step % 90 == 60,
                      let action = await base.host.footCard(at: (await base.host.world).map.spawn.point)?.actions.first {
                command = action.start
            }

            if step == 150 { _ = await switching.setLanguage(.pseudo) }
            if step == 300 { _ = await switching.setLanguage(.ja) }
            if let command {
                for run in runs { _ = await run.host.send(command) }
                _ = await switching.send(command)
            }
            for run in runs { _ = await run.host.tick(realSeconds: 0.5) }
            _ = await switching.tick(realSeconds: 0.5)
            let expected = try await save(base.host)
            let switchedSave = try await save(switching)
            XCTAssertEqual(switchedSave, expected, "language switch changed save at step \(step)")
            for run in runs where run.language != .ja {
                let languageSave = try await save(run.host)
                XCTAssertEqual(languageSave, expected, "language changed save at step \(step)")
            }
            await inspectRuns(step)
        }

        for run in runs {
            XCTAssertGreaterThan(run.auditor.inspectedCount, 0, "runtime auditor did not inspect \(run.language.rawValue)")
            XCTAssertTrue(run.auditor.violations.isEmpty,
                          "runtime perception audit has \(Set(run.auditor.violations.map(\.rule)))")
        }

        let intentionallyUnwrapped = "表を通さない文"
        // ja-ok: PseudoCheck must prove that an unwrapped Japanese test sample is detected.
        XCTAssertEqual(PseudoCheck.unwrapped(["⟦表の文⟧", intentionallyUnwrapped]), [intentionallyUnwrapped])
    }
}
