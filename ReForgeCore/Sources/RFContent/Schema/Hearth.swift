import RFKernel

/// 火床の定義(焚き火と炉が同じ形を使う。序盤の設計 W-02a)。時間はどれもゲーム秒、率は千分率。持ち主: U21
///
/// 燃える速さ(1 ゲーム秒あたり減る燃料。単位はゲーム秒 × 1000)
///   = 段の係数 ×(1000 + structurePermille × 灯りの中のほかの建造物の数)/ 1000 + 夜作業中なら nightWorkPermille。
/// 埋めてあれば、全体に bankedPermille を掛ける。
public struct HearthDef: Codable, Equatable, Sendable {
    /// 燃料の上限(R1 の焚き火は 12 時間)。
    public var capSeconds: Int
    /// 燃料 1 個で足される時間(枝 3 時間・木 6 時間・木炭 10 時間)。
    public var fuels: [ItemID: Int]
    /// 段の下限(くすぶり・ちらつき・燃えている・盛ん の順に 4 つ)。残りがこれより多ければその段。
    /// 例 [0, 10800, 21600, 32400]。
    public var thresholds: [Int]
    /// 段ごとの灯りの半径(消えている から 盛ん まで 5 つ)。
    public var light: [Int]
    /// 段ごとの燃える速さの係数(千分率。5 つ。消えているは 0)。
    public var burnPermille: [Int]
    /// 灯りの中のほかの建造物 1 つあたりの増し(既定 100)。
    public var structurePermille: Int?
    /// その火の灯りで夜作業をしている間の足し(既定 250)。
    public var nightWorkPermille: Int?
    /// 埋めたときの減りの率(既定 333 = 3 分の 1)。
    public var bankedPermille: Int?
    /// 埋めたときの灯りの半径(既定 1)。
    public var bankedLight: Int?
    /// 薪の山に積める数(既定 12)。
    public var pileMax: Int?
    /// 薪の山に積む物(番がくべる物)。nil なら薪の山を持たない。
    public var pileItem: ItemID?
    /// 番は燃料がこれを切るたびに薪の山から 1 つくべる(既定 21600 = 6 時間)。
    public var tendBelowSeconds: Int?
    /// 火が夜明けまで消えなかった夜を数えるカウンタ(埋み火の夜も数える)。
    public var nightsCounter: CounterID?
    /// 建て終えたときの燃料(既定 0 = 消えている)。
    public var initialSeconds: Int?
    /// プレイヤーの「点け直す」に、燃えている別の火(火種)が要るか(既定 true)。
    /// 火起こしのような確率の点け方は、内容の行為(効果 hearth .ignite)で書く。
    public var needsFlame: Bool?
    /// 点けたとき(効果 ignite・点け直し)に、燃料がこれより少なければここまで入れる(残り火から移した火は 4 時間)。
    /// nil は足さない(燃料が無ければ点かない)。
    public var igniteSeconds: Int?

    public init(capSeconds: Int, fuels: [ItemID: Int], thresholds: [Int], light: [Int], burnPermille: [Int],
                structurePermille: Int? = nil, nightWorkPermille: Int? = nil, bankedPermille: Int? = nil,
                bankedLight: Int? = nil, pileMax: Int? = nil, pileItem: ItemID? = nil, tendBelowSeconds: Int? = nil,
                nightsCounter: CounterID? = nil, initialSeconds: Int? = nil, needsFlame: Bool? = nil,
                igniteSeconds: Int? = nil) {
        self.igniteSeconds = igniteSeconds
        self.capSeconds = capSeconds
        self.fuels = fuels
        self.thresholds = thresholds
        self.light = light
        self.burnPermille = burnPermille
        self.structurePermille = structurePermille
        self.nightWorkPermille = nightWorkPermille
        self.bankedPermille = bankedPermille
        self.bankedLight = bankedLight
        self.pileMax = pileMax
        self.pileItem = pileItem
        self.tendBelowSeconds = tendBelowSeconds
        self.nightsCounter = nightsCounter
        self.initialSeconds = initialSeconds
        self.needsFlame = needsFlame
    }
}

/// 効果から火床に対してすること(内容の「くべる」「火を起こす」「火を埋める」)。
public enum HearthEffectOp: Codable, Hashable, Sendable {
    /// 燃料を足す(材料は行為の cost で払う)。消えていれば足すだけで、点けるのは ignite。
    case addFuel(item: ItemID, quantity: Int)
    /// 消えた火を点ける。定義の igniteSeconds まで燃料を入れる(必ず点く)。埋めた火は起こす。
    case ignite
    /// 火を埋める(減りが少なく、灯りは小さい。起こすと戻る)。
    case bank
}
