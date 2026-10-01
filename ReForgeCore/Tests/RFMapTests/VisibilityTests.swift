import Foundation
import XCTest
@testable import RFMap

/// 視界: 昼 8・夜 −3・松明 +4、未踏/既知/視界内の 3 状態、発見。
final class VisibilityTests: XCTestCase {
    func testRadiusRule() {
        let v = VisionRule.original
        XCTAssertEqual(v.radius(isNight: false, hasTorch: false), 8)
        XCTAssertEqual(v.radius(isNight: true, hasTorch: false), 5)
        XCTAssertEqual(v.radius(isNight: false, hasTorch: true), 12)
        XCTAssertEqual(v.radius(isNight: true, hasTorch: true), 9)
        XCTAssertEqual(VisionRule(baseRadius: 3).radius(isNight: true, hasTorch: false), 2, "最小 2")
    }

    func testThreeStates() {
        var layer = VisibilityLayer(size: MapSize(width: 64, height: 64))
        let a = GridPoint(10, 10), far = GridPoint(50, 50)
        XCTAssertEqual(layer.state(at: a), .unseen)
        layer.update(center: a, radius: 8)
        XCTAssertEqual(layer.state(at: a), .visible)
        XCTAssertEqual(layer.state(at: GridPoint(18, 10)), .visible, "半径ちょうどは見える")
        XCTAssertEqual(layer.state(at: GridPoint(16, 16)), .unseen, "円の外(6²+6² > 8²)")
        XCTAssertEqual(layer.state(at: far), .unseen)

        layer.update(center: far, radius: 8)
        XCTAssertEqual(layer.state(at: a), .explored, "離れると既知(暗い地形だけ)に戻る")
        XCTAssertEqual(layer.state(at: far), .visible)
        XCTAssertEqual(layer.state(at: GridPoint(30, 30)), .unseen)
        XCTAssertEqual(layer.state(at: GridPoint(-1, 0)), .unseen, "地図の外")

        // 既知は消えない
        layer.clearView()
        XCTAssertEqual(layer.state(at: far), .explored)
        XCTAssertEqual(layer.state(at: a), .explored)
    }

    func testNightShrinksAndTorchExtends() {
        var m = MapFixture.r1Seed7
        let o = m.landmarks.base.center
        let probe = GridPoint(o.x, o.y + 7)
        m.updateVision(at: o, isNight: true, hasTorch: false)
        XCTAssertEqual(m.visibility(at: probe), .explored, "夜は半径 5")
        m.updateVision(at: o, isNight: true, hasTorch: true)
        XCTAssertEqual(m.visibility(at: probe), .visible, "松明で半径 9")
    }

    func testInitialKnowledgeIsBasePlusThree() {
        let m = MapFixture.r1Seed7
        let b = m.landmarks.base
        // 拠点 +3 の長方形はすべて既知以上
        for y in (b.minCorner.y - 3)...(b.maxCorner.y + 3) {
            for x in (b.minCorner.x - 3)...(b.maxCorner.x + 3) {
                XCTAssertNotEqual(m.visibility(at: GridPoint(x, y)), .unseen)
            }
        }
        XCTAssertEqual(m.visibility(at: b.center), .visible)
        XCTAssertEqual(m.visibility(at: m.landmarks.mountainCenter), .unseen, "岩山は霧の中")
    }

    func testWalkingDiscoversPlacementsAndDeposits() {
        var m = MapFixture.r1Seed7
        XCTAssertFalse(m.surface.placements[.farWreck]!.isDiscovered)
        XCTAssertFalse(m.surface.deposits[.outcrop]!.isDiscovered)
        let u1 = m.updateVision(at: m.landmarks.farWreck, isNight: false, hasTorch: false)
        XCTAssertTrue(u1.discoveredPlacements.contains(.farWreck))
        XCTAssertTrue(m.surface.placements[.farWreck]!.isDiscovered)
        XCTAssertGreaterThan(u1.newlyExplored, 0)
        let u2 = m.updateVision(at: m.landmarks.outcrop, isNight: false, hasTorch: false)
        XCTAssertTrue(u2.discoveredDeposits.contains(.outcrop))
        // 2 回目は新しい発見にならない
        let u3 = m.updateVision(at: m.landmarks.outcrop, isNight: false, hasTorch: false)
        XCTAssertFalse(u3.discoveredDeposits.contains(.outcrop))
        XCTAssertEqual(u3.newlyExplored, 0)
    }

    func testCodableRoundTrip() throws {
        var layer = VisibilityLayer(size: MapSize(width: 200, height: 130))
        layer.update(center: GridPoint(5, 5), radius: 8)
        layer.update(center: GridPoint(150, 120), radius: 12)
        layer.markExplored(from: GridPoint(60, 60), to: GridPoint(70, 66))
        let back = try JSONDecoder().decode(VisibilityLayer.self, from: JSONEncoder().encode(layer))
        XCTAssertEqual(back, layer)
        XCTAssertEqual(back.exploredCells, layer.exploredCells)
        XCTAssertEqual(back.exploredCount, layer.exploredCount)
    }
}
