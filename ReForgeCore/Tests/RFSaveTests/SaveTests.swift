import Foundation
import RFKernel
import RFSave
import RFTestSupport
import RFWorld
import XCTest

final class SaveTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let rig = try TestRig.publicOnly()
        let w = rig.factory.newWorld(seed: 11)
        let e = SaveEnvelope(slot: .dawn(day: 1), world: w, content: [ContentStamp(layer: "public", version: "fixture-1")])
        XCTAssertEqual(try SaveCodec.decode(SaveCodec.encode(e)), e)
    }

    /// 古い版は移行を 1 つずつ通して読む。移行が無ければ読まない(壊れた状態で始めない)。
    func testMigrationChain() throws {
        let rig = try TestRig.publicOnly()
        let e = SaveEnvelope(slot: .resume, world: rig.factory.newWorld(seed: 1), content: [])
        var tree = try JSONDecoder().decode(Value.self, from: SaveCodec.encode(e))
        guard case .object(var o) = tree else { return XCTFail(String(describing: tree).prefix(300).description) }
        o["schemaVersion"] = .int(0)
        o["legacyField"] = .string("x")
        tree = .object(o)
        let old = try JSONEncoder().encode(tree)
        XCTAssertThrowsError(try SaveCodec.decode(old)) { XCTAssertEqual($0 as? SaveCodecError, .missingMigration(from: 0)) }
        let m = SaveMigration(from: 0) { t in
            if case .object(var o) = t { o["legacyField"] = nil; t = .object(o) }
        }
        XCTAssertEqual(try SaveCodec.decode(old, migrations: [m]).world, e.world)
    }

    func testRejectsNewerSchemaAndNonSaves() throws {
        XCTAssertThrowsError(try SaveCodec.decode(Data(#"{"format":"reforge.save","schemaVersion":999}"#.utf8))) {
            XCTAssertEqual($0 as? SaveCodecError, .tooNew(999))
        }
        XCTAssertThrowsError(try SaveCodec.decode(Data(#"{"x":1}"#.utf8)))
    }
}
