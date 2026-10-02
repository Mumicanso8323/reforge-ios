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
    /// 炉の熱(炉のモジュールだけ。W-03・P-04)。nil の火床は熱を持たない(焚き火・古い形の炉)。持ち主: U22
    public var furnace: FurnaceHeatDef?

    public init(capSeconds: Int, fuels: [ItemID: Int], thresholds: [Int], light: [Int], burnPermille: [Int],
                structurePermille: Int? = nil, nightWorkPermille: Int? = nil, bankedPermille: Int? = nil,
                bankedLight: Int? = nil, pileMax: Int? = nil, pileItem: ItemID? = nil, tendBelowSeconds: Int? = nil,
                nightsCounter: CounterID? = nil, initialSeconds: Int? = nil, needsFlame: Bool? = nil,
                igniteSeconds: Int? = nil, furnace: FurnaceHeatDef? = nil) {
        self.igniteSeconds = igniteSeconds
        self.furnace = furnace
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
    /// 消えた火を点ける。定義の igniteSeconds まで燃料を入れる。埋めた火は起こす。
    /// chancePermille があれば、その確率でだけ点く(失敗しても行為の cost は払ったまま)。行為をした人が skill を
    /// 持っていれば skillChancePermille になる。乱数は決定的な流れ "hearth"。省略はどれも必ず点く。
    case ignite(chancePermille: Int? = nil, skill: SkillID? = nil, skillChancePermille: Int? = nil)
    /// 火を埋める(減りが少なく、灯りは小さい。起こすと戻る)。
    case bank
}

/// 炉の熱(序盤の設計 §3.3・W-03・P-04)。温度は ℃ の整数、時間はゲーム秒。持ち主: U22
///
/// - 冷えた炉は、予熱(HearthOp.preheat。preheatFuel を払う)で preheatSeconds かけて workTemp まで上がる。
/// - workTemp 以上の間は、入口の燃料を burnPerHour の速さで使い、熱を保つ(燃料ごとの上限 maxTempByFuel)。
/// - 燃料が無いと 1 時間に coolPerHour 下がる。workTemp を切ると止まり、もう一度予熱が要る。
/// - workTemp 以上の間だけ処理が進み、RuleBook の燃料の条件はこの火床で燃えている燃料で満たす(入口から 1 単位ごとに取らない)。
/// 数は R1 の仮値(nil は既定)。JSON の [ItemID: Int] は {"charcoal": 400} の形。
public struct FurnaceHeatDef: Codable, Equatable, Sendable {
    /// 処理が進む温度(既定 1100)。
    public var workTemp: Int?
    /// 上限(既定 1300)。
    public var maxTemp: Int?
    /// 燃料が来ないときの 1 時間の下がり(既定 200)。
    public var coolPerHour: Int?
    /// 冷えた炉の温度(既定 20。これより下がらない)。
    public var ambientTemp: Int?
    /// 予熱にかかる時間(既定 5400 = 1.5 時間)。
    public var preheatSeconds: Int?
    /// 予熱に払う燃料(既定 木炭 2)。
    public var preheatFuel: [ItemID: Int]?
    /// 熱を保つのに 1 時間に使う燃料(千分率。既定 木炭 400・石炭 300)。並びの順ではなく ID の順に探す。
    public var burnPerHour: [ItemID: Int]?
    /// その燃料で届く温度の上限(既定 薪 900)。書いていない燃料は maxTemp。
    public var maxTempByFuel: [ItemID: Int]?
    /// 熱い間の灯りの半径(既定 3)。
    public var hotLight: Int?

    public init(workTemp: Int? = nil, maxTemp: Int? = nil, coolPerHour: Int? = nil, ambientTemp: Int? = nil,
                preheatSeconds: Int? = nil, preheatFuel: [ItemID: Int]? = nil, burnPerHour: [ItemID: Int]? = nil,
                maxTempByFuel: [ItemID: Int]? = nil, hotLight: Int? = nil) {
        self.workTemp = workTemp
        self.maxTemp = maxTemp
        self.coolPerHour = coolPerHour
        self.ambientTemp = ambientTemp
        self.preheatSeconds = preheatSeconds
        self.preheatFuel = preheatFuel
        self.burnPerHour = burnPerHour
        self.maxTempByFuel = maxTempByFuel
        self.hotLight = hotLight
    }

    public var work: Int { workTemp ?? 1100 }
    public var max: Int { maxTemp ?? 1300 }
    public var cool: Int { coolPerHour ?? 200 }
    public var ambient: Int { ambientTemp ?? 20 }
    public var preheat: Int { preheatSeconds ?? 5400 }
    public var preheatCost: [ItemID: Int] { preheatFuel ?? ["charcoal": 2] }
    public var burn: [ItemID: Int] { burnPerHour ?? ["charcoal": 400, "coal": 300] }
    public func cap(_ fuel: ItemID) -> Int { Swift.min(max, (maxTempByFuel ?? ["wood": 900])[fuel] ?? max) }
    public var light: Int { hotLight ?? 3 }
}
