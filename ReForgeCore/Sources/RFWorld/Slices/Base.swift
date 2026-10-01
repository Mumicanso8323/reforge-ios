import RFKernel

/// 拠点。持ち主: RFBase。人口・収容は placements と people から計算する(保存しない。RFBase.BaseRules)。
public struct BaseState: Codable, Equatable, Sendable {
    /// 拠点グレード(1 = 野営地。R2 で上がる)。
    public var grade: Int = 1
    /// 拠点の範囲(地表)。灯りの範囲・夜に出られる範囲の基準。
    public var area: GridRect?
    /// 建造物に使った材料(片付けたら同じ物・同じ来歴で戻すため)。建造物の実体 → 材料の山。
    public var spent: [EntityID: [CostLot]] = [:]

    public init() {}
}
