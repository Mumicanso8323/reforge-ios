import Foundation
import RFKernel
import RFMap
import RFPresent
import RFWorld
import XCTest

/// A-07 台本の書く・読むの往復。
final class ReplayScriptTests: XCTestCase {
    private func sample() -> ReplayScript {
        ReplayScript(seed: 7, seconds: 12.5, commands: [
            .init(step: 0, command: .narrative(.advanceScene)),
            .init(step: 3, command: .crew(.walk(to: WorldPoint(.surface, GridPoint(4, -2))))),
            .init(step: 9, command: .time(.sleep)),
        ])
    }

    func testCommandsRoundTripThroughJSON() throws {
        let commands = sample().commands.map(\.command)
        let data = try JSONEncoder().encode(commands)
        XCTAssertEqual(try JSONDecoder().decode([Command].self, from: data), commands)
    }

    func testAfterRoundTripsAndOldScriptsWithoutItStillLoad() throws {
        var s = sample()
        s.commands[1].after = 7.5
        let back = try ReplayScript.decode(s.encoded())
        XCTAssertEqual(back.commands[1].after, 7.5)
        XCTAssertNil(back.commands[0].after)
        // after の無い古い台本(欄ごと無い JSON)も読める
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample().encoded()) as? [String: Any])
        var commands = try XCTUnwrap(object["commands"] as? [[String: Any]])
        for i in commands.indices { commands[i].removeValue(forKey: "after") }
        object["commands"] = commands
        let old = try ReplayScript.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old, sample())
    }

    func testScriptRoundTripsThroughData() throws {
        let s = sample()
        XCTAssertEqual(try ReplayScript.decode(s.encoded()), s)
    }

    func testScriptRoundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = sample()
        try s.write(to: url)
        XCTAssertEqual(try ReplayScript.read(from: url), s)
    }

    func testBrokenOrUnknownVersionIsRejected() throws {
        XCTAssertThrowsError(try ReplayScript.decode(Data("not json".utf8)))
        var s = sample()
        s.version = 99
        XCTAssertThrowsError(try ReplayScript.decode(s.encoded()))
    }
}
