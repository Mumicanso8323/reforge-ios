import RFContent
import RFKernel
import RFMatter
import RFWorld

/// 素材の図鑑の 1 行(画面用。名前は認識の層が部品から引く)。
public struct CodexRow: Equatable, Sendable {
    public var name: MatterName
    /// 作ったことがあるか(false は空欄の影)。
    public var made: Bool
    /// 作った中で最良の純度の見当(ノアの手)。空欄は nil。
    public var bestSensed: Purity?
    public var firstSeen: ProvenanceID?
    /// この行に付いた命名の手がかり(聞いたもの)。
    public var hints: [HintID]
}

/// 図鑑。作った物は試作の結果で埋まり、空欄は「図鑑の空欄」の手がかり(HintDef.target)が載ると影で出る。
/// 空欄が次の目標になる(命名からの類推。order.md §5.4 の導線 4)。
public enum Codex {
    /// 作った物を図鑑に入れる(同じ名前なら最良の純度を更新)。
    static func note(_ nb: inout NotebookState, name: MatterName, purity: Purity, record: ProvenanceID) {
        if let i = nb.codex.firstIndex(where: { $0.name == name }) {
            if purity > nb.codex[i].bestPurity { nb.codex[i].bestPurity = purity }
        } else {
            nb.codex.append(CodexEntry(name: name, bestPurity: purity, firstSeen: record))
        }
    }

    /// 図鑑の行(作った順、続いてまだ埋まっていない空欄を手がかりの順に)。
    /// 空欄の名前は部品の一部だけでもよい(「精鉄板」= 精・鉄・板。剛柔を問わない)。作った名前がその部品を全部含めば埋まる。
    public static func rows(_ nb: NotebookState, content: ContentDB) -> [CodexRow] {
        let heardTargets: [(HintID, MatterName)] = nb.hints.keys.sorted().compactMap { id in
            content.hints[id]?.target.map { (id, $0) }
        }
        var rows = nb.codex.map { e in
            CodexRow(name: e.name, made: true, bestSensed: HandSense.estimate(e.bestPurity), firstSeen: e.firstSeen,
                     hints: heardTargets.filter { covers(e.name, $0.1) }.map(\.0))
        }
        var blanks: [MatterName] = []
        for (_, name) in heardTargets where !blanks.contains(name) && !nb.codex.contains(where: { covers($0.name, name) }) {
            blanks.append(name)
        }
        for name in blanks {
            rows.append(CodexRow(name: name, made: false, bestSensed: nil, firstSeen: nil,
                                 hints: heardTargets.filter { $0.1 == name }.map(\.0)))
        }
        return rows
    }

    /// 作った名前が空欄の名前の部品を全部含むか。
    public static func covers(_ made: MatterName, _ target: MatterName) -> Bool {
        target.parts.allSatisfy { made.parts.contains($0) }
    }
}
