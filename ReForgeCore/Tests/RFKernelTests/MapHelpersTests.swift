import RFKernel
import XCTest

final class KernelMapHelpersTests: XCTestCase {
    /// 地図の担当の型(RFMap/Kernel)と同じ振る舞い。置き換えても地図の生成の結果が変わらない。
    func testGridAndRandomHelpersMatchMapBranch() {
        let p = GridPoint(2, 3)
        XCTAssertEqual(p + GridPoint(1, -1), GridPoint(3, 2))
        XCTAssertEqual(p.distanceSquared(to: GridPoint(5, 7)), 25)
        XCTAssertEqual(p.distance(to: GridPoint(5, 7)), 5)
        XCTAssertEqual(p.neighbors8.first, GridPoint(2, 2))
        XCTAssertEqual(p.neighbors8.count, 8)
        var r = SeededRandom(state: 1)
        let u = r.unit()
        XCTAssertTrue(u >= 0 && u < 1)
        XCTAssertEqual(Purity.percent(25), Purity(percent: 25))
        XCTAssertEqual(Purity.percent(25).fraction, 0.25)
    }
}
