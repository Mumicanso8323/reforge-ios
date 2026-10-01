import RFSurvival
import RFContent
import RFKernel
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// RFSurvival の受け入れテストの置き場(docs/architecture/F-work-units.md の該当の単位)。
final class SurvivalSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(SurvivalSystem().handle(foreign, &ctx), .notMine)
    }
}
