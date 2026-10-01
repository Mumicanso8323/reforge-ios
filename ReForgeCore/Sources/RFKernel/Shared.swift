/// 複数の層が条件・記録で共通に使う小さな列挙。

/// 1 日の中の位置。
public enum DayPhase: String, Codable, CaseIterable, Sendable {
    /// 昼。リアルタイムで進む。
    case day
    /// 日没。時計は止まり、帯で「夜作業」か「寝る」を選ぶ(画面は止めない)。
    case dusk
    /// 夜作業。行為ごとに決まった時間だけ進む(試作 2 時間など)。
    case nightWork
}

/// 来歴に残す行為の種類。後の開示・条件・日誌が「あのとき自分がしたこと」をこれで探す。
/// 新しい種類は末尾に足す(名前を変えるとセーブと条件が壊れる)。
public enum ActKind: String, Codable, CaseIterable, Sendable {
    // 作る
    case trialed            // 試作した
    case crafted            // 手で作った
    case produced           // ラインが作った(モジュール単位で数をまとめる)
    case designed           // ライン札にした
    // 置く・建てる
    case placed, moved, dismantled
    case built, demolished
    // 選ぶ
    case chose              // 出来事の選択肢を選んだ
    case used, kept         // 有限の品を使った / 取っておいた
    case consumed           // 食べた・飲んだ・燃やした
    // 探す
    case discovered, entered, scavenged, gathered, mined
    // 人
    case met, joined, left, died, assigned, talked, rescued
    // 戦う
    case fought, defeated, fled, wasInjured
    // 知る
    case learned, observed, heardHint, researched, acquiredSkill
    // 周回
    case rewound, failed, continuedWithLoss, chapterEnded
    // 工業の行為(開示の引き金になりやすいもの)
    // observed(観測した)は「知る」の並びにある。観測の夜の数は来歴の count と追跡カウンタで数える
    case analyzed           // 分析した
    case repaired           // 直した
    case salvagedPart       // 有限の部品(残骸の区画など)を取り外した・解体した
    case rebuiltPart        // 取り外した部品を自分の工業で作り直した
    case overridden         // 出来事が仲間の配属などを上書きした
    // 末尾に足す(保存は名前で持つので順番は効かないが、並びは足した順に保つ)
    case raided             // 蓄えを奪われた(獣など。U9)
    case achieved           // 目標を果たした・結末に着いた(U11)
    case destroyed          // 置いた物が壊された(爆発・襲撃など。U16。直せば repaired)
}

/// 数の比較(条件で使う)。
public enum Comparison: String, Codable, Sendable {
    case lt, le, eq, ge, gt, ne

    public func test(_ a: Int64, _ b: Int64) -> Bool {
        switch self {
        case .lt: a < b
        case .le: a <= b
        case .eq: a == b
        case .ge: a >= b
        case .gt: a > b
        case .ne: a != b
        }
    }
}
