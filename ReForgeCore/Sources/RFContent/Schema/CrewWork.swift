import RFKernel

// 人の自動化の規則(序盤の設計 W-04・INV-O8・INV-O10)。持ち主: U22(RFCrew)。JSON の最上位キー "crewWork"
// (単一の設定。後の層が勝つ)。無ければ今どおり(人の速さも働ける人数も縛らない)。値は R1 の仮値で、
// 序盤の設計 v0.4 で直る。nil の項目は下の既定値。

/// 人の自動化の規則。
public struct CrewWorkDef: Codable, Equatable, Sendable {
    /// 仲間が採取と手作業(採る・伐る・掘る・叩く・溶かす。配属 gather の行為)をする速さ(千分率)。既定 600。
    /// 運搬と建設には掛けない(1000)。
    public var gatherWorkPermille: Int?
    /// 仲間に頼めるのは、ノアが手で 1 度終えた行為だけ(INV-O8)。既定 true。
    public var requireHandFirst: Bool?
    /// 焚き火の段(HearthLevel の raw: 消えている 0・くすぶり 1・ちらつき 2・燃えている 3・盛ん 4)ごとの火の枠。
    /// 既定 [0, 0, 0, 1, 2]。
    public var fireSlots: [Int]?
    /// 寝床の数を読む建造物の provides のキー。既定 "housing"。
    public var bedTag: String?
    /// 寝床のうちノアが使う数(寝床の枠 = 寝床 − これ)。既定 1。
    public var noahBeds: Int?
    /// 火の番をした人が翌日の昼に働ける時間(ゲーム時間)。既定 4。
    public var keeperNextDayHours: Int?
    /// 火の番を頼むのに、ノアが手で 1 度やっている必要がある行為の種類(くべる。InteractionDef.handFamily)。
    /// nil なら縛らない。
    public var tendFamily: HandFamilyID?

    public init(gatherWorkPermille: Int? = nil, requireHandFirst: Bool? = nil, fireSlots: [Int]? = nil,
                bedTag: String? = nil, noahBeds: Int? = nil, keeperNextDayHours: Int? = nil,
                tendFamily: HandFamilyID? = nil) {
        self.gatherWorkPermille = gatherWorkPermille
        self.requireHandFirst = requireHandFirst
        self.fireSlots = fireSlots
        self.bedTag = bedTag
        self.noahBeds = noahBeds
        self.keeperNextDayHours = keeperNextDayHours
        self.tendFamily = tendFamily
    }

    public var gatherPermille: Int { gatherWorkPermille ?? 600 }
    public var handFirst: Bool { requireHandFirst ?? true }
    public var slotsByLevel: [Int] { fireSlots ?? [0, 0, 0, 1, 2] }
    public var beds: String { bedTag ?? "housing" }
    public var noahBedCount: Int { noahBeds ?? 1 }
    public var keeperHours: Int { keeperNextDayHours ?? 4 }
}
