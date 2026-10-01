import Foundation
import RFKernel
import RFMap
import RFWorld
import XCTest

final class WorldTests: XCTestCase {
    /// 来歴: 「工業の初めて」の索引は種類ごとに最初の記録を指す。
    func testLedgerFirstsAndDescendants() {
        var l = ProvenanceLedger()
        func add(_ act: ActKind, _ s: SubjectRef, _ inputs: [ProvenanceID] = []) -> ProvenanceID {
            l.append { ProvenanceRecord(id: $0, at: .zero, day: 1, run: 1, actor: nil, act: act, subject: s, inputs: inputs) }
        }
        let a = add(.crafted, .item("wood"))
        let b = add(.crafted, .item("wood"), [a])
        let c = add(.placed, .module("furnace", EntityID(1)), [b])
        _ = add(.placed, .module("furnace", EntityID(2)))
        XCTAssertEqual(l.first(.crafted, .item("wood")), a)
        XCTAssertEqual(l.first(.placed, .module("furnace", nil)), c)
        XCTAssertEqual(l.descendants(of: a).map(\.id), [b, c])
    }

    func testEmptyWorldRoundTrips() throws {
        let map = MapState(layers: [:], baseArea: nil, spawn: WorldPoint(.surface, GridPoint(0, 0)))
        let w = WorldState(seed: 1, map: map)
        XCTAssertEqual(try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(w)), w)
    }
}
