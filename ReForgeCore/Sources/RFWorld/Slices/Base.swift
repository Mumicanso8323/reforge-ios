import RFKernel

/// 拠点。持ち主: RFBase。人口・収容は placements と people から計算する(保存しない)。
public struct BaseState: Codable, Equatable, Sendable {
    /// 拠点グレード(1 = 野営地)。
    public var grade: Int = 1
    /// 拠点の範囲(地表)。灯りの範囲・夜に出られる範囲の基準。
    public var area: GridRect?

    public init() {}
}
