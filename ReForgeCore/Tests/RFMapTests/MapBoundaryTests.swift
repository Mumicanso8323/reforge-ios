import RFKernel
import RFMap
import XCTest

/// 地図の担当の受け入れテストの置き場(F-work-units.md U1)。境界の型の最小の確かめ。
final class MapBoundaryTests: XCTestCase {
    func testLayerTerrainSetAndGet() {
        var l = MapLayer(size: GridSize(width: 4, height: 3), palette: ["grass"], terrain: Array(repeating: 0, count: 12))
        l.setTerrain("rock", at: GridPoint(3, 2))
        XCTAssertEqual(l.terrain(at: GridPoint(3, 2)), "rock")
        XCTAssertEqual(l.terrain(at: GridPoint(0, 0)), "grass")
        XCTAssertNil(l.terrain(at: GridPoint(4, 0)))
    }
}
