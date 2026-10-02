import RFKernel

/// 仲間の得意分野の振る舞い(MECH-05・BEAT-19)。持ち主: U5(RFCrew が読む)。
///
/// 能力(数値の強さ)ではなく、配属したときに「何をするか」の範囲を変える。ノアにも同じ形で書ける
/// (能力の画面に出す値はコンテンツが決める。)。
/// そばの人への効き(精神力の戻りを早めるなど)は振る舞いでなく、PersonDef.auras の範囲の効果で書く。
public enum CrewBehavior: Codable, Hashable, Sendable {
    /// 見張りに立っているとき、敵が守る人(nil ならノア)に radius マス以内まで近づいたら、敵と守る人の間に出る。
    case interpose(protect: PersonID?, radius: Int)
}
