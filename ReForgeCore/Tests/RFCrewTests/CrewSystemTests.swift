import RFCrew
import RFContent
import RFKernel
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// RFCrew の受け入れテストの置き場(docs/architecture/F-work-units.md の該当の単位)。
final class CrewSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(CrewSystem().handle(foreign, &ctx), .notMine)
    }
}
