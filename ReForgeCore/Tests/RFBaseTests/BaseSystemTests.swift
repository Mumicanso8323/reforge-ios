import RFBase
import RFContent
import RFKernel
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// RFBase の受け入れテストの置き場(docs/architecture/F-work-units.md の該当の単位)。
final class BaseSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .time(.sleep)
        XCTAssertEqual(BaseSystem().handle(foreign, &ctx), .notMine)
    }
}
