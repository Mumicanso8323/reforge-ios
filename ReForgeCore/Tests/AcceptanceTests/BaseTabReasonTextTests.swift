import ReForgeEngine
import RFTestSupport
import XCTest

/// 拠点のタブに残す 2 つの文(止まった建物の理由 .stopped(reason) と、運搬が止まった理由 RouteState.blocked)は、
/// 指示や不足の文にせず名詞句にする(game-designer-2 10/10)。重ねた内容の文に、不足・指示の形が無いことを見る。
/// 鍵は本体の定数から引き、文は内容から読む(このテストは物語の語を持たない)。公開の層だけの版は元の文のままなので、
/// 非公開の層があるときだけ回す。失敗の文には鍵と当たった形だけを出す。
final class BaseTabReasonTextTests: XCTestCase {
    /// 止まった建物の理由(Modules.blocker が返す鍵)と、運搬の blocked の鍵。
    static let keys: [TextID] = [
        ProductionText.noInput, ProductionText.noAux, ProductionText.noPower, ProductionText.noWorker,
        ProductionText.outputFull, ProductionText.depleted, ProductionText.noDeposit,
        FurnaceHeat.furnaceCold,
        HaulRules.unreachable, HaulRules.noHaulers,
    ]
    /// 不足・指示の文の形(一般の語)。
    static let forbidden = ["あと", "足りない", "がない", "できない", "来ていない", "いない"]

    func testStoppedAndHaulReasonsAreNounPhrases() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        let content = try TestContent.full()
        var bad: [String] = []
        for key in Self.keys {
            guard let text = content.texts[key], !text.isEmpty else {
                bad.append("\(key.rawValue): 文が無い")
                continue
            }
            for word in Self.forbidden where text.contains(word) {
                bad.append("\(key.rawValue): 「\(word)」")
            }
        }
        XCTAssertEqual(bad, [], "止まった理由・運搬の理由の文に不足・指示の形がある(鍵: 当たった形)")
    }
}
