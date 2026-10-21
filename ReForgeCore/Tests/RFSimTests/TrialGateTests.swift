import RFContent
import RFKernel
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// M-01 の門は公開の束には置かない。この試験だけが公開の束に小さな重ねを載せる。
final class TrialGateTests: XCTestCase {
    private let gateCounter: CounterID = "counter.test.trial.gate"
    private let orderCounter: CounterID = "counter.test.trial.order"
    private let releaseCounter: CounterID = "counter.test.trial.release"
    private let stat: StatID = "stat.test.trial.clock"
    private let heldFailure: FailureRuleID = "failure.test.trial.held"
    private let ordinaryFailure: FailureRuleID = "failure.test.trial.ordinary"
    private let firstEvent: EventID = "event.test.trial.first"
    private let secondEvent: EventID = "event.test.trial.second"

    /// `resume` 以外は JSON の重ねで読む。resume は関連値の無い enum の JSON 形に試験が依存しないよう、読んだ後に置く。
    private func content(mode: TrialGateMode? = .fence, holds: TrialHoldsDef? = nil,
                         resume: TrialResume? = .shiftThresholds) throws -> ContentDB {
        var db = try TestContent.publicOnly()
        let modeJSON = mode.map { #", "mode": "\#($0.rawValue)""# } ?? ""
        let holdsJSON: String
        if let holds {
            let events = (holds.events ?? []).map { #""\#($0.rawValue)""# }.joined(separator: ",")
            let failures = (holds.failures ?? []).map { #""\#($0.rawValue)""# }.joined(separator: ",")
            holdsJSON = #", "holds": { "research": \#(holds.research == true ? "true" : "false"), "events": [\#(events)], "failures": [\#(failures)] }"#
        } else {
            holdsJSON = ""
        }
        try ContentLoader.apply(json: Data(#"""
        {
          "trialGate": {
            "when": { "counter": { "id": "counter.test.trial.gate", "cmp": "ge", "value": 1 } }
            \#(modeJSON)\#(holdsJSON),
            "onRelease": [
              { "setCounter": { "id": "counter.test.trial.release", "value": 1 } },
              { "setCounter": { "id": "counter.test.trial.order", "value": 5 } }
            ]
          },
          "stats": [ { "id": "stat.test.trial.clock", "initial": 100, "perDay": 10 } ],
          "failureRules": [
            { "id": "failure.test.trial.held", "when": { "stat": { "id": "stat.test.trial.clock", "cmp": "ge", "value": 250 } }, "cause": "text.test.cause" },
            { "id": "failure.test.trial.ordinary", "when": { "counter": { "id": "counter.test.trial.ordinary", "cmp": "ge", "value": 1 } }, "cause": "text.test.cause" }
          ],
          "events": [
            { "id": "event.test.trial.first", "priority": 2,
              "trigger": { "on": ["hour"], "when": { "always": {} } },
              "effects": [ { "setCounter": { "id": "counter.test.trial.order", "value": 10 } } ] },
            { "id": "event.test.trial.second", "priority": 1,
              "trigger": { "on": ["hour"], "when": { "always": {} } },
              "effects": [ { "counter": { "id": "counter.test.trial.order", "add": 1 } } ] },
            { "id": "event.test.trial.free", "priority": 0,
              "trigger": { "on": ["hour"], "when": { "always": {} } },
              "effects": [ { "counter": { "id": "counter.test.trial.free", "add": 1 } } ] }
          ]
        }
        """#.utf8), to: &db, name: "trial-gate-test")
        db.trialGate?.resume = resume
        return db
    }

    private func world(_ content: ContentDB, seed: UInt64 = 7, closed: Bool = true, stat value: Int = 100) -> WorldState {
        var world = TestRig(content: content).factory.newWorld(seed: seed)
        world.clock.held = false
        world.clock.now = GameTime(seconds: 3_300) // the next fixed step crosses an hour
        world.survival.stats[stat] = Milli(raw: Int64(value))
        if closed { world.narrative.counters[gateCounter] = 1 }
        return world
    }

    private func trialSimulation(_ content: ContentDB, fullGame: Bool) -> Simulation {
        Simulation(content: content, entitlements: Entitlements(fullGame: fullGame))
    }

    private func heldContent(mode: TrialGateMode? = .fence, resume: TrialResume? = .shiftThresholds) throws -> ContentDB {
        try content(mode: mode,
                    holds: TrialHoldsDef(research: true, events: [firstEvent, secondEvent], failures: [heldFailure]),
                    resume: resume)
    }

    /// B.1-1: 門を置かない既存内容は、権利の有無で 1 bit も変わらない。
    func testNoGateIsIdenticalWithoutEntitlement() throws {
        let content = try TestContent.publicOnly()
        var trial = world(content, closed: false)
        var full = trial
        let commands: [Command] = [.time(.startNightWork), .time(.sleep)]
        for command in commands {
            let without = trialSimulation(content, fullGame: false).apply(command, to: &trial)
            let with = trialSimulation(content, fullGame: true).apply(command, to: &full)
            XCTAssertEqual(without.events, with.events)
            XCTAssertEqual(without.rejection, with.rejection)
            XCTAssertEqual(without.steps, with.steps)
            XCTAssertEqual(without.warnings, with.warnings)
        }
        XCTAssertEqual(trial, full)
    }

    /// B.1-2 と「研究を始める」一覧。続ける研究は門で断らない。
    func testFenceKeepsClockAndOtherWorkMovingButHoldsOnlyResearchStartsAndNamedEvents() throws {
        let content = try heldContent()
        let trial = trialSimulation(content, fullGame: false)
        var world = world(content)

        // この配列が「研究を始める命令」の正本。case を追加したらここも足す。
        let starts: [Command] = [
            .research(.select(research: "research.test.basics")),
            .research(.learnSkill(person: .noah, skill: "skill.test.instant")),
        ]
        var reached = 0
        for command in starts {
            let report = trial.apply(command, to: &world)
            XCTAssertEqual(report.rejection?.reason, "reason.trial.locked")
            reached += report.events.filter { $0 == .trialReached }.count
        }
        for command in [Command.research(.stopLearning(person: .noah)), .research(.nightStudy(person: .noah))] {
            XCTAssertNotEqual(trial.apply(command, to: &world).rejection?.reason, "reason.trial.locked")
        }
        XCTAssertNotEqual(trial.apply(.production(.handwork(id: "handwork.test.cord", input: nil, holding: true)), to: &world).rejection?.reason,
                          "reason.trial.locked", "柵は手の作業・生産そのものを止めない")

        let before = world.clock.now
        let report = trial.runSteps(24, &world)
        XCTAssertGreaterThan(world.clock.now, before, "柵の中でも時計と通常の系は進む")
        XCTAssertEqual(world.narrative.counters["counter.test.trial.free"], 1, "待たせない出来事は起きる")
        XCTAssertEqual(world.trial?.deferred.map(\.id), [firstEvent.rawValue, secondEvent.rawValue])
        XCTAssertFalse(world.narrative.fired.keys.contains(firstEvent))
        XCTAssertEqual(reached, 1)
        XCTAssertEqual(trial.runSteps(1, &world).events.filter { $0 == .trialReached }.count, 0)
        XCTAssertEqual(world.trial?.deferred.filter { $0.kind == .event }.count, 2, "同じ出来事を二重に積まない")
    }

    /// B.1-3: 解放は効果、待ち列、失敗の再判定の順で 1 回だけ行う。
    func testFenceReleaseAppliesEffectThenDeferredEventsOnceAndResearchCanStart() throws {
        let content = try heldContent()
        var world = world(content)
        _ = trialSimulation(content, fullGame: false).runSteps(24, &world)
        XCTAssertEqual(world.trial?.deferred.count, 2)

        let full = trialSimulation(content, fullGame: true)
        let release = full.syncEntitlements(&world)
        XCTAssertEqual(world.narrative.counters[releaseCounter], 1)
        XCTAssertEqual(world.narrative.counters[orderCounter], 11, "解放効果 → first の set → second の add")
        XCTAssertEqual(world.trial?.deferred, [])
        XCTAssertNotNil(world.trial?.releasedAt)
        XCTAssertEqual(release.events.filter { $0 == .trialReleased }.count, 1)
        XCTAssertNotEqual(full.apply(.research(.select(research: "research.test.basics")), to: &world).rejection?.reason,
                          "reason.trial.locked")
        XCTAssertEqual(full.syncEntitlements(&world).events.filter { $0 == .trialReleased }.count, 0)
        _ = trialSimulation(content, fullGame: false).syncEntitlements(&world)
        XCTAssertNil(world.trial?.releasedAt, "払い戻しで再び閉じたら、次の解放を待つ")
        XCTAssertEqual(full.syncEntitlements(&world).events.filter { $0 == .trialReleased }.count, 1)
    }

    /// B.1-3b: 待たせた失敗だけが列に入り、R-2 の余裕は切った時の値から測る。
    func testHeldFailuresDeferOnceAndResumeWithConfiguredRule() throws {
        let content = try heldContent()
        let trial = trialSimulation(content, fullGame: false)

        var held = world(content, stat: 100)
        _ = trial.runSteps(1, &held) // cutStats = 100
        held.survival.stats[stat] = Milli(raw: 260) // しきい値 250 を柵の中で越える
        _ = trial.runSteps(1, &held)
        XCTAssertTrue(held.run.isActive)
        let deferred = try XCTUnwrap(held.trial?.deferred.first { $0.kind == .failure })
        XCTAssertEqual(deferred.id, heldFailure.rawValue)
        XCTAssertEqual(deferred.stats?[stat], 260)
        XCTAssertEqual(held.trial?.deferred.filter { $0.kind == .failure }.count, 1)

        held.survival.stats[stat] = Milli(raw: 230) // 季節で下がって、しきい値の手前で外れる
        _ = trial.runSteps(1, &held)
        let full = trialSimulation(content, fullGame: true)
        _ = full.syncEntitlements(&held)
        XCTAssertTrue(held.run.isActive)
        XCTAssertEqual(held.survival.stats[stat]?.raw, 230)
        XCTAssertEqual(held.trial?.shifts?[heldFailure]?[stat], 130)
        held.survival.stats[stat] = Milli(raw: 380)
        _ = full.runSteps(1, &held)
        XCTAssertFalse(held.run.isActive, "230 からではなく、門を切った時の余裕 150 を使い切って失敗する")

        var valley = world(content, stat: 100)
        _ = trial.runSteps(1, &valley)
        valley.survival.stats[stat] = Milli(raw: 230)
        _ = trial.runSteps(1, &valley)
        valley.survival.stats[stat] = Milli(raw: 180)
        _ = full.syncEntitlements(&valley)
        XCTAssertEqual(valley.trial?.shifts?[heldFailure]?[stat], 80)
        valley.survival.stats[stat] = Milli(raw: 330)
        _ = full.runSteps(1, &valley)
        XCTAssertFalse(valley.run.isActive)

        var ordinary = world(content, stat: 100)
        ordinary.narrative.counters["counter.test.trial.ordinary"] = 1
        _ = trial.runSteps(1, &ordinary)
        XCTAssertFalse(ordinary.run.isActive, "holds に無い規則は柵の中でも通常どおり")

        let judgeContent = try heldContent(resume: .judgeAtRelease)
        var judge = world(judgeContent, stat: 300)
        _ = trialSimulation(judgeContent, fullGame: false).runSteps(1, &judge)
        _ = trialSimulation(judgeContent, fullGame: true).syncEntitlements(&judge)
        XCTAssertFalse(judge.run.isActive, "judgeAtRelease は外れたステップで普通に判定する")
    }

    /// B.1-3b2: どの時点で外しても、外れた後の余裕(試験用の 1 step = 1 day)は同じ。
    func testShiftThresholdsKeepsSameRemainingDaysAcrossTrialSavesAndFullBuildLoad() throws {
        let content = try heldContent()
        let trial = trialSimulation(content, fullGame: false)
        let full = trialSimulation(content, fullGame: true)

        func daysUntilFailure(_ world: inout WorldState) -> Int {
            var days = 0
            while world.run.isActive && days < 30 {
                world.survival.stats[stat, default: .zero].raw += 10
                _ = full.runSteps(1, &world)
                days += 1
            }
            return days
        }
        func released(afterTrialValue value: Int, reload: Bool) throws -> WorldState {
            var world = self.world(content, stat: 100)
            _ = trial.runSteps(1, &world)
            world.survival.stats[stat] = Milli(raw: Int64(value))
            _ = trial.runSteps(1, &world)
            if reload { world = try SaveCodec.decode(SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))).world }
            _ = full.syncEntitlements(&world)
            return world
        }

        var immediate = try released(afterTrialValue: 100, reload: false)
        var later = try released(afterTrialValue: 180, reload: false)
        var latest = try released(afterTrialValue: 230, reload: true)
        XCTAssertEqual(immediate.trial?.cutStats?[stat], 100)
        XCTAssertEqual(latest.trial?.cutStats?[stat], 100, "切った時の値は保存し直しても残る")
        let immediateDays = daysUntilFailure(&immediate)
        XCTAssertEqual(immediateDays, 15)
        XCTAssertEqual(daysUntilFailure(&later), immediateDays)
        XCTAssertEqual(daysUntilFailure(&latest), immediateDays, "製品版が体験版の保存を初めて読む口も同じ")
    }

    /// B.1-3c: 製品版で初めて読むときも、解放処理は最初の step に一度だけ。
    func testFullBuildLoadReleasesDeferredWorkOnlyOnce() throws {
        let content = try heldContent()
        var saved = world(content)
        _ = trialSimulation(content, fullGame: false).runSteps(24, &saved)
        saved = try SaveCodec.decode(SaveCodec.encode(SaveEnvelope(slot: .resume, world: saved, content: []))).world
        let full = trialSimulation(content, fullGame: true)
        XCTAssertEqual(full.runSteps(1, &saved).events.filter { $0 == .trialReleased }.count, 1)
        XCTAssertEqual(full.runSteps(1, &saved).events.filter { $0 == .trialReleased }.count, 0)
    }

    /// B.1-4: freeze は時計・命令・寝る見込みまで同じ世界のまま止める。
    func testFreezeStopsClockCommandsAndSleepForecastUntilEntitled() throws {
        let content = try content(mode: .freeze, holds: nil, resume: nil)
        let trial = trialSimulation(content, fullGame: false)
        var world = world(content)
        _ = trial.syncEntitlements(&world) // 札のしるし(noticed)は先に立てておく。止めた後に変わらないことを見る
        let before = world
        XCTAssertEqual(trial.advance(&world, realSeconds: 1).steps, 0)
        XCTAssertEqual(trial.runSteps(3, &world).steps, 0)
        XCTAssertNil(trial.forecastSleep(world))
        XCTAssertEqual(trial.apply(.time(.sleep), to: &world).rejection?.reason, "reason.trial.locked")
        XCTAssertEqual(world, before)
        XCTAssertGreaterThan(trialSimulation(content, fullGame: true).runSteps(1, &world).steps, 0)
    }

    /// B.1-5: 待ち列は保存に残り、trial の無い既存の保存も読める。
    func testSaveRoundTripKeepsDeferredItemsAndOlderSavesDecodeWithoutTrial() throws {
        let content = try heldContent()
        var world = world(content, stat: 300)
        _ = trialSimulation(content, fullGame: false).runSteps(24, &world)
        let saved = try SaveCodec.decode(SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))).world
        XCTAssertEqual(saved.trial?.deferred, world.trial?.deferred)
        XCTAssertTrue(saved.trial?.deferred.contains { $0.kind == .event } == true)
        XCTAssertTrue(saved.trial?.deferred.contains { $0.kind == .failure && $0.stats?[stat] != nil } == true)

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RFSaveTests/Fixtures/save-v1-dev-7ea0791.json")
        XCTAssertNil(try SaveCodec.decode(Data(contentsOf: fixture)).world.trial)
    }

    /// B.1-6: JSON の optional な形と、不完全な失敗再開指定を固定する。
    func testTrialGateJSONOptionalFieldsAndFailureResumeValidation() throws {
        var none = try TestContent.publicOnly()
        XCTAssertNil(none.trialGate)
        try ContentLoader.apply(json: Data(#"""
        { "trialGate": { "when": { "always": {} } } }
        """#.utf8), to: &none, name: "trial-no-optionals")
        XCTAssertEqual(none.trialGate?.mode, nil)
        XCTAssertNil(none.trialGate?.holds)
        XCTAssertEqual(TrialGate.mode(none), .fence)

        var holds = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(#"""
        { "trialGate": {
          "when": { "always": {} }, "mode": "freeze",
          "holds": { "research": true, "events": [], "failures": ["failure.test.doom"] }
        } }
        """#.utf8), to: &holds, name: "trial-with-holds")
        XCTAssertEqual(holds.trialGate?.mode, .freeze)
        XCTAssertEqual(holds.trialGate?.holds?.research, true)
        XCTAssertTrue(ContentValidator.validate(holds).contains { $0.level == .error && $0.rule == "trialGate.resume" })

        var danglingCondition = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(#"""
        { "trialGate": { "when": { "eventFired": { "id": "event.test.trial.missing" } } } }
        """#.utf8), to: &danglingCondition, name: "trial-dangling-condition")
        XCTAssertTrue(ContentValidator.validate(danglingCondition).contains { $0.level == .error },
                      "門の条件に書いた ID も検証する")
    }
}
