/// 遊びの記録の節目(最上位キー "playtestMarks"。PT-B4)。
/// 条件が初めて成り立った時に、端末の中の記録へ 1 件 `mark` を書く。ID だけを記録し、物語の文は持たない。
/// 条件は決定的に判定する(chance・trigger は使わない。検証が見る)。
public struct PlaytestMarkDef: ContentDef, Equatable {
    public var id: String
    public var when: Condition

    public init(id: String, when: Condition) {
        self.id = id
        self.when = when
    }
}

extension ContentValidator {
    /// 節目の ID は mark. で始まり、条件に chance・trigger を使わない。
    static func playtestMarksWellFormed(_ db: ContentDB, _ out: inout [Issue]) {
        for (key, def) in db.playtestMarks.sorted(by: { $0.key < $1.key }) {
            if key != def.id || !def.id.hasPrefix("mark.") {
                out.append(Issue(level: .error, rule: "playtestMark.id", message: "\(key) の ID は mark. で始め、キーと同じにする"))
            }
            def.when.walk { c in
                switch c {
                case .chance, .trigger:
                    out.append(Issue(level: .error, rule: "playtestMark.deterministic",
                                     message: "\(key) の条件に chance・trigger は使えない"))
                case .firstTime:
                    // 引き金の来歴が無いので、節目の評価では成り立たない。ledger(atLeast: 1) で書く
                    out.append(Issue(level: .error, rule: "playtestMark.firstTime",
                                     message: "\(key) の条件に firstTime は使えない(ledger の atLeast で書く)"))
                default: break
                }
            }
        }
    }
}
