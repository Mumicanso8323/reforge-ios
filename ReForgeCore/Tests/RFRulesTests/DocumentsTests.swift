import RFContent
import RFKernel
import RFRules
import RFTestSupport
import RFWorld
import XCTest

final class DocumentsTests: XCTestCase {
    /// 資料は条件が成り立つと記録に載る(状態を持たない。order の順)。
    func testDocumentsAppearWhenConditionHolds() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        XCTAssertEqual(Documents.available(in: ctx.world, content: rig.content).map(\.id), ["doc.test.first"])
        ctx.learn("fact.test.alpha")
        XCTAssertEqual(Documents.available(in: ctx.world, content: rig.content).map(\.id),
                       ["doc.test.first", "doc.test.later"])
        XCTAssertEqual(rig.content.texts[rig.content.documents["doc.test.first"]!.body], "試験の書き付けの全文。")
    }
}
