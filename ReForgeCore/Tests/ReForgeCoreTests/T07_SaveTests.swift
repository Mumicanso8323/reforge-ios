import XCTest
@testable import ReForgeCore

/// TEST-07: 保存 → 復元で GameState が等価。復帰時に壁時計が 8 時間進んでいても状態が変わらない。
final class T07_SaveTests: XCTestCase {
    let g = Fixture.game

    func testRoundTripMidDay() throws {
        var s = g.newGame(seed: .max - 12345)
        s = g.must(.gather(.wood), s)
        s = g.must(.gather(.scavenge), s)
        s = g.tick(s, deltaSeconds: 73.25)
        s = g.mustSleep(g.tick(s, deltaSeconds: 200))
        s = g.tick(s, deltaSeconds: 11.5)
        let data = try SaveCodec.encode(SaveFile(state: s, purchases: Purchases(adsRemoved: true)))
        let back = try SaveCodec.decode(data)
        XCTAssertEqual(back.state, s)
        XCTAssertEqual(back.schemaVersion, 1)
        XCTAssertEqual(back.purchases.adsRemoved, true)
        // 復元した状態から同じ行動を続けても同じ結果(乱数の状態も保存されている)
        XCTAssertEqual(g.perform(.gather(.wood), on: back.state), g.perform(.gather(.wood), on: s))
    }

    func testRoundTripAfterGameOver() throws {
        var s = g.idleDays(3, g.newGame(seed: 1).with(ID.water, 0))
        XCTAssertEqual(s.outcome, .gameOver(.dehydration))
        s = try SaveCodec.decode(SaveCodec.encode(SaveFile(state: s))).state
        XCTAssertEqual(s.outcome, .gameOver(.dehydration))
    }

    func testRejectsUnknownSchema() throws {
        let data = try SaveCodec.encode(SaveFile(state: g.newGame(seed: 1)))
        var json = try XCTUnwrap(String(data: data, encoding: .utf8))
        json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        XCTAssertThrowsError(try SaveCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SaveCodecError, .unsupportedSchema(99))
        }
    }

    func testNoOfflineProgress() {
        var s = g.newGame(seed: 2)
        s = g.tick(s, deltaSeconds: 42)
        let resumed = g.resume(s, elapsedWallClock: 8 * 3600)
        XCTAssertEqual(resumed, s)
    }

    func testLogIsCappedAt200() {
        var s = g.newGame(seed: 2)
        s.actionPointsLeft = 1000
        for _ in 0..<250 { s = g.must(.gather(.water), s) }
        XCTAssertEqual(s.log.count, 200)
    }
}
