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

/// PT-B3 手応え(Frame.pulses)。来歴と出来事から作り、次のフレームには残さず、世界は変えない(INV-B3-2)。
final class PulsesTests: XCTestCase {
    private func rig() throws -> (TestRig, FrameBuilder, WorldState) {
        let rig = try TestRig.publicOnly()
        let builder = FrameBuilder(content: rig.content)
        return (rig, builder, rig.factory.newWorld(seed: 1))
    }

    private func report(_ events: [DomainEvent], rejection: Rejection? = nil) -> StepReport {
        var r = StepReport()
        r.events = events
        r.rejection = rejection
        return r
    }

    /// TEST-B3-1 手作業の 1 単位で unitDone が 1 つだけ入り、次のフレームには残らない。
    func testUnitDoneOnceAndNotCarried() throws {
        let (_, b, w) = try rig()
        let first = b.build(w, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(first.pulses, [], "報告の無い組み立ては手応えを返さない")
        let ev = DomainEvent.itemGained(holder: .person(.noah), stuff: .item("wood"), quantity: 1, record: nil)
        let second = b.build(w, revision: 2, previous: first, report: report([ev]))
        let units = second.pulses.filter { if case .unitDone = $0 { true } else { false } }
        XCTAssertEqual(units.count, 1)
        guard case .unitDone(_, let count) = units[0] else { return XCTFail() }
        XCTAssertEqual(count, 1)
        let third = b.build(w, revision: 3, previous: second, report: report([]))
        XCTAssertEqual(third.pulses, [], "次のフレームには残らない")
    }

    /// TEST-B3-2 断られた命令で rejected が理由つきで入る。
    func testRejectedCarriesReason() throws {
        let (rig, b, w) = try rig()
        let reason = TextID("reason.test.pulse")
        let r = Rejection(reason)
        let f = b.build(w, revision: 1, previous: nil, report: report([], rejection: r))
        let expected = Perceiver(content: rig.content, world: w, language: b.language, markFallback: b.markFallback)
            .rejectionText(reason)
        XCTAssertEqual(f.pulses, [.rejected(reason: expected)])
    }

    /// TEST-B3-3 火が点いた・弱まった・消えたで fire が入る。
    func testFirePulses() throws {
        let (_, b, w) = try rig()
        func fire(_ level: HearthLevel, previous: Frame?) -> Frame {
            b.build(w, revision: (previous?.revision ?? 0) + 1, previous: previous,
                    report: report([.hearthLevelChanged(placement: EntityID(1), level: level)]))
        }
        var f = fire(.burning, previous: nil)
        XCTAssertEqual(f.pulses, [.fire(.lit)])
        f = b.build(w, revision: 3, previous: nil, report: report([
            .hearthLevelChanged(placement: EntityID(1), level: .burning),
            .hearthLevelChanged(placement: EntityID(1), level: .smoldering),
            .hearthLevelChanged(placement: EntityID(1), level: .out)]))
        XCTAssertEqual(f.pulses, [.fire(.lit), .fire(.weakened), .fire(.out)])
    }

    func testFedAndNightAndWorldUnchanged() throws {
        let (_, b, w) = try rig()
        let before = w
        let f = b.build(w, revision: 1, previous: nil, report: report([
            .hearthStoked(placement: EntityID(1)), .phaseChanged(to: .dusk, day: 1)]))
        XCTAssertEqual(f.pulses, [.fed, .nightBegan])
        XCTAssertEqual(w, before, "INV-B3-2 世界は変えない")
    }
}
